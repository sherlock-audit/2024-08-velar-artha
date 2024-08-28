########################################################################
DEPLOYER   : address
INITIALIZED: bool

PARAMS     : public(Parameters)

@external
def __init__():
  self.DEPLOYER    = msg.sender
  self.INITIALIZED = False

@external
def __init__2(params: Parameters):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  assert not self.INITIALIZED       , ERR_INVARIANTS
  self.INITIALIZED = True
  self.PARAMS = params

@external
def set_deployer(new_deployer: address):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  self.DEPLOYER = new_deployer

@external
def set_params(new_params: Parameters):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  self.PARAMS = new_params

########################################################################
# fee computation (borrowing & funding fees)
@external
@view
def dynamic_fees(pool: PoolState) -> DynFees:
    """
    Borrowing fees scale linearly based on pool utilization, from
    MIN_FEE to MAX_FEE.
    Funding fees scale base on the utilization imbalance off of the
    borrowing fee.
    """
    long_utilization : uint256 = self.utilization(pool.base_reserves, pool.base_interest)
    short_utilization: uint256 = self.utilization(pool.quote_reserves, pool.quote_interest)
    borrowing_long   : uint256 = self.check_fee(
      self.scale(self.PARAMS.MAX_FEE, long_utilization))
    borrowing_short  : uint256 = self.check_fee(
      self.scale(self.PARAMS.MAX_FEE, short_utilization))
    funding_long     : uint256 = self.funding_fee(
      borrowing_long, long_utilization,  short_utilization)
    funding_short    : uint256 = self.funding_fee(
      borrowing_short, short_utilization,  long_utilization)
    return DynFees({
        borrowing_long : borrowing_long,
        borrowing_short: borrowing_short,
        funding_long   : funding_long,
        funding_short  : funding_short,
    })

@internal
@pure
def utilization(reserves: uint256, interest: uint256) -> uint256:
    """
    Reserve utilization in percent (rounded down).
    """
    return 0 if (reserves == 0 or interest == 0) else (interest / (reserves / 100))

@internal
@pure
def scale(fee: uint256, utilization: uint256) -> uint256:
    return (fee * utilization) / 100

@internal
@view
def check_fee(fee: uint256) -> uint256:
    if self.PARAMS.MIN_FEE <= fee and fee <= self.PARAMS.MAX_FEE: return fee
    elif fee < self.PARAMS.MIN_FEE                              : return self.PARAMS.MIN_FEE
    else                                                        : return self.PARAMS.MAX_FEE

@internal
@pure
def imbalance(n: uint256, m: uint256) -> uint256:
    return n - m if n >= m else 0

@internal
@view
def funding_fee(base_fee: uint256, col1: uint256, col2: uint256) -> uint256:
  imb: uint256 = self.imbalance(col1, col2)
  if imb == 0: return 0
  else       : return self.check_fee(self.scale(base_fee, imb))

########################################################################
# one-off protocol fee
@external
@view
def static_fees(collateral: uint256) -> Fee:
  fee      : uint256 = collateral / self.PARAMS.PROTOCOL_FEE
  remaining: uint256 = collateral - fee
  return Fee({x: collateral, fee: fee, remaining: remaining})

########################################################################
# position properties
@external
@view
def is_legal_position(pool: PoolState, position: PositionState) -> bool:
    min_size: bool = position.collateral >= (self.PARAMS.MIN_LONG_COLLATERAL if position.long else
                                             self.PARAMS.MIN_SHORT_COLLATERAL)
    # Max size limits are not really enforceable since users can just
    # open multiple identical positions.
    # This can be used as a pause button (set to zero to prevent new
    # positions from being opened).
    max_size: bool = position.collateral <= (self.PARAMS.MAX_LONG_COLLATERAL if position.long else
                                             self.PARAMS.MAX_SHORT_COLLATERAL)
    min_leverage: bool = position.leverage >= (self.PARAMS.MIN_LONG_LEVERAGE if position.long else
                                               self.PARAMS.MIN_SHORT_LEVERAGE)
    max_leverage: bool = position.leverage <= (self.PARAMS.MAX_LONG_LEVERAGE if position.long else
                                               self.PARAMS.MAX_SHORT_LEVERAGE)
    return min_size and max_size and min_leverage and max_leverage

@external
@view
def is_liquidatable(position: PositionState, pnl: PnL) -> bool:
    """
    A position becomes liquidatable when its current value is less than
    a configurable fraction of the initial collateral, scaled by
    leverage.
    """
    # Assume liquidation bots are able to check and liquidate positions
    # every N seconds.
    # We would like to avoid the situation where a position's value goes
    # negative (due to price fluctuations and fee obligations) during
    # this period.
    # Roughly, the most a positions value can change is
    #   leverage * asset price variance + fees
    # If N is small, this expression will be ~the price variance.
    # E.g. if N = 60 and we expect a maximal price movement of 1%/minute
    # we could set LIQUIDATION_THRESHOLD to 1 (* some constant to be on the
    # safe side).
    percent : uint256 = self.PARAMS.LIQUIDATION_THRESHOLD * position.leverage
    required: uint256 = (position.collateral * percent) / 100
    return not (pnl.remaining > required)

@external
@view
def liquidation_fees(amt: uint256) -> Fee:
  fee      : uint256 = amt / self.PARAMS.LIQUIDATION_FEE
  remaining: uint256 = amt - fee
  return Fee({x: amt, fee: fee, remaining: remaining})

# eof

# GL can be thought of as a game with 4 participants:
#  the protocol
#  users
#  LPs
#  liquidators
#
#  - prices are given by an external oracle
#  - users deposit collateral tokens to open long or short positions in
#    an asset with leverage, to speculate on price movements or earn
#    funding fees
#  - users pay funding fees to eachother based on the imbalance between
#    long and short interest
#  - users also pay a dynamic borrowing fee each block (set based on
#    current demand for reserves) to LPs
#  - both fees are paid from the user's collateral, which therefore
#    decreases over time. once the remaining collateral drops below a
#    certain threshold, a position becomes liquidatable and can be
#    closed by anyone
# -  positions cannot be kept open indefinitely. this is to balance the
#    preference of users to keep positions open with the preference of LPs
#    to be able to withdraw reserve tokens
#  - LPs take the opposite side of user positions by providing reserve tokens
#    which are used to pay out profitable positions when they are closed
#  - when user positions close at a loss, the LPs profit by keeping some of the
#    user's collateral
#  - liquidators monitor the chain to find liquidatable positions and close
#    them. they are rewarded by keeping a portion of the positions remaining
#    collateral and additionally out-of-band via liquidation incentives
#  - the protocol handles the accounting needed to maintain the sytem invariants:
#    * any open position can always be closed
#        close(open(collateral)) = collateral + pnl - fees
#    * funding payments match
#        sum(funding_received) = sum(funding_paid)
#
# Here's a basic example to get a feel for how this works in practice
#  - lets say we have a btc/usdt (base/quote) pool and btc price is 50k
#  - lp provides tokens e.g. 10BTC 10*50k USDT
#  - user opens long position with 50k USDT of collateral and 3x leverage
#  - system determines worst case payout if price goes to infinity:
#    3 btc (for shorts the worst case price is zero so the worst case payout
#    would be 150k USDT)
#  - locks 3 of the 10BTC in the pool
#  - at some point in the future, the user closes the position
#  - all calculations happen at close time
#  - system determines accumulated fees and pnl, deducts fees from
#    and adds pnl to collateral
#  - pool keeps collateral and sends user (remaining collateral + pnl)
#    as BTC at the current price
#  - longs provide quote collateral and shorts provide base collateral
#    (not strictly necessary but helps balance out pool reserves since
#    generally one side will lose tokens when the other side wins tokens)
#  - if the value of the position were to dip below a small percentage
#    of the initial collateral a liquidation bot would call liquidate,
#    which would close the position
#
# state is spread across several contracts:
#   - core owns actual collateral and reserve tokens
#   - pools handles accounting of those balances
#   - positions stores position state
#   - fees maintains state needed to compute the fee obligations
#       funding paid = funding received
#       borrowing paid
#     (fees uses params.dynamic_fees which takes the current pool state as input
#      and therefore fees.update must be called whenever anything that changes
#      the pool state is called)

########################################################################
from vyper.interfaces import ERC20
import math           as Math
import params         as Params
import pools          as Pools
import fees           as Fees
import positions      as Positions

MATH       : public(Math)
PARAMS     : public(Params)
POOLS      : public(Pools)
FEES       : public(Fees)
POSITIONS  : public(Positions)

API        : public(address)
COLLECTOR  : public(address)

DEPLOYER   : address
INITIALIZED: bool

@external
def __init__():
  self.DEPLOYER    = msg.sender
  self.INITIALIZED = False

@external
def __init__2(
  math     : address,
  params   : address,
  pools    : address,
  fees     : address,
  positions: address,
  collector: address,
  api      : address):

  assert msg.sender == self.DEPLOYER, ERR_INVARIANTS
  assert not self.INITIALIZED       , ERR_INVARIANTS
  self.INITIALIZED = True

  self.MATH        = Math(math)
  self.PARAMS      = Params(params)
  self.POOLS       = Pools(pools)
  self.FEES        = Fees(fees)
  self.POSITIONS   = Positions(positions)
  self.COLLECTOR   = collector
  self.API         = api

@internal
def _INTERNAL():
  assert (msg.sender == self.API or msg.sender == self), ERR_PERMISSIONS

@external
def set_collector(new_collector: address):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  self.COLLECTOR = new_collector

########################################################################
# this works because each pool gets its own copy of all contracts
@internal
def INVARIANTS(id: uint256, base_token: address, quote_token: address):
  pool         : PoolState = self.POOLS.lookup(id)
  base_balance : uint256   = ERC20(base_token).balanceOf(self)
  quote_balance: uint256   = ERC20(quote_token).balanceOf(self)
  assert base_balance  >= (pool.base_reserves  + pool.base_collateral),  ERR_INVARIANTS
  assert quote_balance >= (pool.quote_reserves + pool.quote_collateral), ERR_INVARIANTS
  assert pool.base_reserves  >= pool.base_interest,  ERR_INVARIANTS
  assert pool.quote_reserves >= pool.quote_interest, ERR_INVARIANTS

########################################################################
@external
def fresh(
  symbol     : String[65],
  base_token : address,
  quote_token: address,
  lp_token   : address):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  assert not self.POOLS.exists_pair(base_token, quote_token), ERR_PRECONDITIONS
  assert not self.POOLS.exists_pair(quote_token, base_token), ERR_PRECONDITIONS
  assert not self.POOLS.exists_lp(lp_token),                  ERR_PRECONDITIONS

  user: address   = msg.sender
  pool: PoolState = self.POOLS.fresh(symbol, base_token, quote_token, lp_token)
  fees: FeeState  = self.FEES.fresh(pool.id)

  log Create(user, pool.id)

########################################################################
@external
def mint(
  id          : uint256,
  base_token  : address,
  quote_token : address,
  lp_token    : address,
  base_amt    : uint256,
  quote_amt   : uint256,
  ctx         : Ctx) -> uint256:

  self._INTERNAL()

  user        : address   = tx.origin
  total_supply: uint256   = ERC20(lp_token).totalSupply()
  pool        : PoolState = self.POOLS.lookup(id)
  lp_amt      : uint256   = self.POOLS.calc_mint(id, base_amt, quote_amt, total_supply, ctx)

  assert pool.base_token  == base_token , ERR_PRECONDITIONS
  assert pool.quote_token == quote_token, ERR_PRECONDITIONS
  assert pool.lp_token    == lp_token   , ERR_PRECONDITIONS
  assert base_amt > 0 or quote_amt > 0  , ERR_PRECONDITIONS
  assert lp_amt > 0                     , ERR_PRECONDITIONS

  assert ERC20(base_token).transferFrom(user, self, base_amt, default_return_value=True), "ERR_ERC20"
  assert ERC20(quote_token).transferFrom(user, self, quote_amt, default_return_value=True), "ERR_ERC20"
  assert ERC20Plus(lp_token).mint(user, lp_amt), "ERR_ERC20"

  self.POOLS.mint(id, base_amt, quote_amt)
  self.FEES.update(id)

  self.INVARIANTS(id, base_token, quote_token)

  log Mint(user, ctx, pool, total_supply, lp_amt, base_amt, quote_amt)

  return lp_amt

########################################################################
@external
def burn(
  id          : uint256,
  base_token  : address,
  quote_token : address,
  lp_token    : address,
  lp_amt      : uint256,
  ctx         : Ctx) -> Tokens:

  self._INTERNAL()

  user        : address   = tx.origin
  total_supply: uint256   = ERC20(lp_token).totalSupply()
  pool        : PoolState = self.POOLS.lookup(id)
  amts        : Tokens    = self.POOLS.calc_burn(id, lp_amt, total_supply, ctx)
  base_amt    : uint256   = amts.base
  quote_amt   : uint256   = amts.quote

  assert pool.base_token  == base_token , ERR_PRECONDITIONS
  assert pool.quote_token == quote_token, ERR_PRECONDITIONS
  assert pool.lp_token    == lp_token   , ERR_PRECONDITIONS
  assert base_amt > 0 or quote_amt > 0  , ERR_PRECONDITIONS
  assert lp_amt > 0                     , ERR_PRECONDITIONS

  assert ERC20(base_token).transfer(user, base_amt, default_return_value=True), "ERR_ERC20"
  assert ERC20(quote_token).transfer(user, quote_amt, default_return_value=True), "ERR_ERC20"
  assert ERC20Plus(lp_token).burn(user, lp_amt), "ERR_ERC20"

  self.POOLS.burn(id, base_amt, quote_amt)
  self.FEES.update(id)

  self.INVARIANTS(id, base_token, quote_token)

  log Burn(user, ctx, pool, total_supply, lp_amt, base_amt, quote_amt)

  return amts

########################################################################
@external
def open(
  id          : uint256,
  base_token  : address,
  quote_token : address,
  long        : bool,
  collateral0 : uint256,
  leverage    : uint256,
  ctx         : Ctx) -> PositionState:

  self._INTERNAL()

  user       : address   = tx.origin
  pool       : PoolState = self.POOLS.lookup(id)

  cf         : Fee       = self.PARAMS.static_fees(collateral0)
  fee        : uint256   = cf.fee
  collateral : uint256   = cf.remaining

  assert pool.base_token  == base_token , ERR_PRECONDITIONS
  assert pool.quote_token == quote_token, ERR_PRECONDITIONS
  assert collateral > 0                 , ERR_PRECONDITIONS
  assert fee > 0                        , ERR_PRECONDITIONS

  if long: assert ERC20(quote_token).transferFrom(user, self, collateral0), "ERR_ERC20"
  else   : assert ERC20(base_token).transferFrom(user, self, collateral0),  "ERR_ERC20"

  # transfer protocol fees to separate contract
  if long: assert ERC20(quote_token).transfer(self.COLLECTOR, fee), "ERR_ERC20"
  else   : assert ERC20(base_token).transfer(self.COLLECTOR, fee),  "ERR_ERC20"

  position: PositionState = self.POSITIONS.open(user, id, long, collateral, leverage, ctx)
  self.POOLS.open(id, position.collateral_tagged, position.interest_tagged)
  self.FEES.update(id)

  self.INVARIANTS(id, base_token, quote_token)

  log Open(user, ctx, pool, position)

  return position

########################################################################
@external
def close(
  id          : uint256,
  base_token  : address,
  quote_token : address,
  position_id : uint256,
  ctx         : Ctx) -> PositionValue:

  self._INTERNAL()

  user    : address       = tx.origin
  pool    : PoolState     = self.POOLS.lookup(id)
  position: PositionState = self.POSITIONS.lookup(position_id)

  assert pool.base_token  == base_token , ERR_PRECONDITIONS
  assert pool.quote_token == quote_token, ERR_PRECONDITIONS
  assert id   == position.pool          , ERR_PRECONDITIONS
  assert user == position.user          , ERR_PRECONDITIONS

  value    : PositionValue = self.POSITIONS.close(position_id, ctx)
  base_amt : uint256       = self.MATH.eval(0, value.deltas.base_transfer)
  quote_amt: uint256       = self.MATH.eval(0, value.deltas.quote_transfer)
  self.POOLS.close(id, value.deltas)
  self.FEES.update(id)

  if base_amt > 0:
    assert ERC20(base_token).transfer(user, base_amt, default_return_value=True), "ERR_ERC20"
  if quote_amt > 0:
    assert ERC20(quote_token).transfer(user, quote_amt, default_return_value=True), "ERR_ERC20"

  self.INVARIANTS(id, base_token, quote_token)

  log Close(user, ctx, pool, value)
  return value

########################################################################
@external
def liquidate(
  id         : uint256,
  base_token : address,
  quote_token: address,
  position_id: uint256,
  ctx        : Ctx) -> PositionValue:

  self._INTERNAL()

  # identical to close()
  user    : address       = tx.origin #liquidator
  pool    : PoolState     = self.POOLS.lookup(id)
  position: PositionState = self.POSITIONS.lookup(position_id)

  assert pool.base_token  == base_token                  , ERR_PRECONDITIONS
  assert pool.quote_token == quote_token                 , ERR_PRECONDITIONS
  assert id == position.pool                             , ERR_PRECONDITIONS
  assert self.POSITIONS.is_liquidatable(position_id, ctx), ERR_PRECONDITIONS

  value    : PositionValue = self.POSITIONS.close(position_id, ctx)
  base_amt : uint256       = self.MATH.eval(0, value.deltas.base_transfer)
  quote_amt: uint256       = self.MATH.eval(0, value.deltas.quote_transfer)
  self.POOLS.close(id, value.deltas)
  self.FEES.update(id)

  base_amt_final : Fee = self.PARAMS.liquidation_fees(base_amt)
  quote_amt_final: Fee = self.PARAMS.liquidation_fees(quote_amt)

  # liquidator gets liquidation fee, user gets whatever is left
  if base_amt_final.fee > 0:
    assert ERC20(base_token).transfer(user, base_amt_final.fee, default_return_value=True), "ERR_ERC20"
  if quote_amt_final.fee > 0:
    assert ERC20(quote_token).transfer(user, quote_amt_final.fee, default_return_value=True), "ERR_ERC20"
  if base_amt_final.remaining > 0:
    assert ERC20(base_token).transfer(position.user, base_amt_final.remaining, default_return_value=True), "ERR_ERC20"
  if quote_amt_final.remaining > 0:
    assert ERC20(quote_token).transfer(position.user, quote_amt_final.remaining, default_return_value=True), "ERR_ERC20"

  self.INVARIANTS(id, base_token, quote_token)

  log Liquidate(user, ctx, pool, value)
  return value

# eof

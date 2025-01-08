# yay
import math      as Math
import params    as Params
import pools     as Pools
import fees      as Fees
import positions as Positions
import ERC20Plus as ERC20Plus

########################################################################
# This is the entry-point contract.
#
# The callgraph is:
#         api --> oracle --> RedstoneExtractor.sol
#          |
#          |
#         core --> ERC20Plus
#        /  |  \
#       /   |   \
#  pools <-fees<-positions
#           |    |
#           |    |
#           params
#
# math is a library called by core, pools, and positions
import core   as Core
import oracle as Oracle

ORACLE: public(Oracle)
CORE  : public(Core)

DEPLOYER   : address
INITIALIZED: bool
LOCK       : public(HashMap[address, uint256])

@external
def __init__():
  self.DEPLOYER    = msg.sender
  self.INITIALIZED = False

@external
def __init__2(
  oracle   : address,
  core     : address):
  assert msg.sender == self.DEPLOYER, ERR_INVARIANTS
  assert not self.INITIALIZED       , ERR_INVARIANTS
  self.INITIALIZED = True

  self.ORACLE = Oracle(oracle)
  self.CORE   = Core(core)

########################################################################
# We take the oracle payload and UI price and if everything checks out
# create a context and proxy the call to core.
@internal
def CONTEXT(
    base_token : address,
    quote_token: address,
    desired    : uint256,
    slippage   : uint256,
    payload    : Bytes[512]
) -> Ctx:
  base_decimals : uint256 = ERC20Plus(base_token).decimals()
  quote_decimals: uint256 = ERC20Plus(quote_token).decimals()
  # this will revert on error
  price         : uint256 = self.ORACLE.price(quote_decimals,
                                              desired,
                                              slippage,
                                              payload)
  return Ctx({
    price         : price,
    base_decimals : base_decimals,
    quote_decimals: quote_decimals,
  })

########################################################################
@external
@nonreentrant("lock")
def mint(
  base_token  : address, #ERC20
  quote_token : address, #ERC20
  lp_token    : address, #ERC20Plus
  base_amt    : uint256,
  quote_amt   : uint256,
  desired     : uint256,
  slippage    : uint256,
  payload     : Bytes[512]
) -> uint256:
  """
  @notice            Provide liquidity to the pool
  @param base_token  Token representing the base coin of the pool (e.g. BTC)
  @param quote_token Token representing the quote coin of the pool (e.g. USDT)
  @param lp_token    Token representing shares of the pool's liquidity
  @param base_amt    Number of base tokens to provide
  @param quote_amt   Number of quote tokens to provide
  @param desired     Price to provide liquidity at (unit price using onchain
                     representation for quote_token, e.g. 1.50$ would be
                     1500000 for USDT with 6 decimals)
  @param slippage    Acceptable deviaton of oracle price from desired price
                     (same units as desired e.g. to allow 5 cents of slippage,
                     send 50000).
  @param payload     Signed Redstone oracle payload
  """
  ctx: Ctx = self.CONTEXT(base_token, quote_token, desired, slippage, payload)
  return self.CORE.mint(1, base_token, quote_token, lp_token, base_amt, quote_amt, ctx)

@external
@nonreentrant("lock")
def burn(
  base_token  : address,
  quote_token : address,
  lp_token    : address,
  lp_amt      : uint256,
  desired     : uint256,
  slippage    : uint256,
  payload     : Bytes[512]
) -> Tokens:
  """
  @notice            Withdraw liquidity from the pool
  @param base_token  Token representing the base coin of the pool (e.g. BTC)
  @param quote_token Token representing the quote coin of the pool (e.g. USDT)
  @param lp_token    Token representing shares of the pool's liquidity
  @param lp_amt      Number of LP tokens to burn
  @param desired     Price to provide liquidity at (unit price using onchain
                     representation for quote_token, e.g. 1.50$ would be
                     1500000 for USDT with 6 decimals)
  @param slippage    Acceptable deviaton of oracle price from desired price
                     (same units as desired e.g. to allow 5 cents of slippage,
                     send 50000).
  @param payload     Signed Redstone oracle payload
  """
  ctx: Ctx = self.CONTEXT(base_token, quote_token, desired, slippage, payload)
  return self.CORE.burn(1, base_token, quote_token, lp_token, lp_amt, ctx)

@external
@nonreentrant("lock")
def open(
  base_token  : address,
  quote_token : address,
  long        : bool,
  collateral0 : uint256,
  leverage    : uint256,
  desired     : uint256,
  slippage    : uint256,
  payload     : Bytes[512]
) -> PositionState:
  """
  @notice            Open a position
  @param base_token  Token representing the base coin of the pool (e.g. BTC)
  @param quote_token Token representing the quote coin of the pool (e.g. USDT)
  @param long        Flag indicating whether to go long or short
  @param collateral0 Collateral tokens to send (long positions are collateralized
                     in quote_token, short positions are collateralized in base token).
  @param leverage    How much leverage to use
  @param desired     Price to provide liquidity at (unit price using onchain
                     representation for quote_token, e.g. 1.50$ would be
                     1500000 for USDT with 6 decimals)
  @param slippage    Acceptable deviaton of oracle price from desired price
                     (same units as desired e.g. to allow 5 cents of slippage,
                     send 50000).
  @param payload     Signed Redstone oracle payload
  """
  ctx: Ctx = self.CONTEXT(base_token, quote_token, desired, slippage, payload)
  return self.CORE.open(1, base_token, quote_token, long, collateral0, leverage, ctx)

@external
@nonreentrant("lock")
def close(
  base_token  : address,
  quote_token : address,
  position_id : uint256,
  desired     : uint256,
  slippage    : uint256,
  payload     : Bytes[512]
) -> PositionValue:
  """
  @notice            Close a position
  @param base_token  Token representing the base coin of the pool (e.g. BTC)
  @param quote_token Token representing the quote coin of the pool (e.g. USDT)
  @param position_id The ID of the position to close
  @param desired     Price to provide liquidity at (unit price using onchain
                     representation for quote_token, e.g. 1.50$ would be
                     1500000 for USDT with 6 decimals)
  @param slippage    Acceptable deviaton of oracle price from desired price
                     (same units as desired e.g. to allow 5 cents of slippage,
                     send 50000).
  @param payload     Signed Redstone oracle payload
  """
  ctx: Ctx = self.CONTEXT(base_token, quote_token, desired, slippage, payload)
  return self.CORE.close(1, base_token, quote_token, position_id, ctx)

@external
@nonreentrant("lock")
def liquidate(
  base_token : address,
  quote_token: address,
  position_id: uint256,
  desired     : uint256,
  slippage    : uint256,
  payload     : Bytes[512]
) -> PositionValue:
  """
  @notice            Liquidate a position
  @dev               This is exactly like close but only the user who opened
                     a position may close a position, whereas anyone may
                     liquidate a position iff it is liquidatable
  @param base_token  Token representing the base coin of the pool (e.g. BTC)
  @param quote_token Token representing the quote coin of the pool (e.g. USDT)
  @param position_id The ID of the position to close
  @param desired     Price to provide liquidity at (unit price using onchain
                     representation for quote_token, e.g. 1.50$ would be
                     1500000 for USDT with 6 decimals)
  @param slippage    Acceptable deviaton of oracle price from desired price
                     (same units as desired e.g. to allow 5 cents of slippage,
                     send 50000).
  @param payload     Signed Redstone oracle payload
  """
  ctx: Ctx = self.CONTEXT(base_token, quote_token, desired, slippage, payload)
  return self.CORE.liquidate(1, base_token, quote_token, position_id, ctx)

# eof

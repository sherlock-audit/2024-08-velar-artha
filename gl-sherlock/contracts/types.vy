### BEGIN types.vy

# Errors
ERR_PRECONDITIONS : constant(String[16]) = "PRECONDITIONS"
ERR_POSTCONDITIONS: constant(String[16]) = "POSTCONDITIONS"
ERR_PERMISSIONS   : constant(String[16]) = "PERMISSIONS"
ERR_INVARIANTS    : constant(String[16]) = "INVARIANTS"

# math.vy
struct Tokens:
  base : uint256
  quote: uint256

# Oracle-certified price and token representations (assumed to be static).
struct Ctx:
  price         : uint256
  base_decimals : uint256
  quote_decimals: uint256

struct Value:
  base                  : uint256
  quote                 : uint256
  base_as_quote         : uint256
  quote_as_base         : uint256
  total_as_base         : uint256
  total_as_quote        : uint256
  have_more_base        : bool
  base_excess_as_base   : uint256
  base_excess_as_quote  : uint256
  quote_excess_as_base  : uint256
  quote_excess_as_quote : uint256

struct Fee:
  x        : uint256
  fee      : uint256
  remaining: uint256

enum OP:
  ADD_
  SUB_
  MUL_
  DIV_

struct Instr:
  op : OP
  arg: uint256

# params.vy
struct Parameters:
  # Fees are stored as a numerator, with the denominator defined in math.vy.
  #
  # Min fee example for 5 second blocks:
  #  1 year     = 6324480 blocks
  #  10% / year ~ 0.000_0016% / block
  #  in math.vy representation: 16
  #
  # Max fee example for 5 second blocks:
  #   8h      = 5760 blocks
  #   4% / 8h ~ 0.000_7% / block
  #   in math.vy representation: 7_000
  #
  MIN_FEE               : uint256
  MAX_FEE               : uint256

  # Fraction of collateral (e.g. 1000).
  PROTOCOL_FEE          : uint256

  # Fraction of remaining collateral (e.g. 2)
  LIQUIDATION_FEE       : uint256

  # Depend on coin decimals.
  MIN_LONG_COLLATERAL   : uint256
  MAX_LONG_COLLATERAL   : uint256
  MIN_SHORT_COLLATERAL  : uint256
  MAX_SHORT_COLLATERAL  : uint256

  # E.g. 1 and 10.
  MIN_LONG_LEVERAGE     : uint256
  MAX_LONG_LEVERAGE     : uint256
  MIN_SHORT_LEVERAGE    : uint256
  MAX_SHORT_LEVERAGE    : uint256

  # C.f. is_liquidatable, e.g. 1.
  LIQUIDATION_THRESHOLD : uint256

struct DynFees:
  borrowing_long : uint256
  borrowing_short: uint256
  funding_long   : uint256
  funding_short  : uint256

# pools.vy
struct PoolState:
  id               : uint256
  symbol           : String[65]
  base_token       : address
  quote_token      : address
  lp_token         : address
  # reserve tokens provided by LPs
  base_reserves    : uint256
  quote_reserves   : uint256
  # total open interest
  base_interest    : uint256
  quote_interest   : uint256
  # collateral tokens provided by users
  base_collateral  : uint256
  quote_collateral : uint256

# fees.vy
struct FeeState:
  id                   : uint256
  t0                   : uint256
  t1                   : uint256
  borrowing_long       : uint256
  borrowing_short      : uint256
  funding_long         : uint256
  funding_short        : uint256
  long_collateral      : uint256
  short_collateral     : uint256
  borrowing_long_sum   : uint256
  borrowing_short_sum  : uint256
  funding_long_sum     : uint256
  funding_short_sum    : uint256
  received_long_sum    : uint256
  received_short_sum   : uint256

struct SumFees:
  funding_paid    : uint256
  funding_received: uint256
  borrowing_paid  : uint256

# positions.vy
enum Status:
  OPEN
  CLOSED
  LIQUIDATABLE

struct PositionState:
  id         : uint256
  pool       : uint256
  user       : address
  status     : Status
  long       : bool
  collateral : uint256
  leverage   : uint256
  interest   : uint256
  entry_price: uint256
  exit_price : uint256
  opened_at  : uint256
  closed_at  : uint256

  collateral_tagged: Tokens
  interest_tagged  : Tokens

struct FeesPaid:
  funding_paid          : uint256
  funding_paid_want     : uint256
  funding_received      : uint256
  funding_received_want : uint256
  borrowing_paid        : uint256
  borrowing_paid_want   : uint256
  remaining             : uint256

struct PnL:
  loss     : uint256
  profit   : uint256
  remaining: uint256
  payout   : uint256

struct Deltas:
  base_interest   : DynArray[Instr, 100]
  quote_interest  : DynArray[Instr, 100]
  base_transfer   : DynArray[Instr, 100]
  base_reserves   : DynArray[Instr, 100]
  base_collateral : DynArray[Instr, 100]
  quote_transfer  : DynArray[Instr, 100]
  quote_reserves  : DynArray[Instr, 100]
  quote_collateral: DynArray[Instr, 100]

struct PositionValue:
  position: PositionState
  fees    : FeesPaid
  pnl     : PnL
  deltas  : Deltas

# core.vy
interface ERC20Plus:
  def decimals()                         -> uint8: view
  def mint(to: address, amt: uint256)    -> bool: nonpayable
  def burn(_from: address, amt: uint256) -> bool: nonpayable

event Create:
  user: indexed(address)
  pool: indexed(uint256)

event Mint:
  user        : indexed(address)
  ctx         : Ctx
  pool        : PoolState
  total_supply: uint256
  lp_amt      : uint256
  base_amt    : uint256
  quote_amt   : uint256

event Burn:
  user        : indexed(address)
  ctx         : Ctx
  pool        : PoolState
  total_supply: uint256
  lp_amt      : uint256
  base_amt    : uint256
  quote_amt   : uint256

event Open:
  user    : indexed(address)
  ctx     : Ctx
  pool    : PoolState
  position: PositionState

event Close:
  user : indexed(address)
  ctx  : Ctx
  pool : PoolState
  value: PositionValue

event Liquidate:
  user : indexed(address)
  ctx  : Ctx
  pool : PoolState
  value: PositionValue

# oracle.vy
interface Extractor:
  def extractPrice(feed_id: bytes32, payload: Bytes[224]) -> (uint256, uint256): view

### END types.vy

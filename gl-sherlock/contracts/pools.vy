########################################################################
import pools as Pools #self
import math  as Math

MATH: public(Math)

CORE: public(address)

DEPLOYER   : address
INITIALIZED: bool

@external
def __init__():
  self.DEPLOYER    = msg.sender
  self.INITIALIZED = False

@external
def __init__2(
  math: address,
  core: address):
  assert msg.sender == self.DEPLOYER, ERR_INVARIANTS
  assert not self.INITIALIZED       , ERR_INVARIANTS
  self.INITIALIZED = True

  self.MATH    = Math(math)
  self.CORE    = core
  self.POOL_ID = 0

@internal
def _INTERNAL():
  assert (msg.sender == self.CORE or msg.sender == self), ERR_PERMISSIONS

########################################################################
POOL_ID: uint256

@internal
def next_pool_id() -> uint256:
  id : uint256 = self.POOL_ID
  nxt: uint256 = id + 1
  self.POOL_ID = nxt
  return nxt

@external
@view
def get_nr_pools() -> uint256:
  return self.POOL_ID

########################################################################
POOL_STORE: HashMap[uint256, PoolState]
PAIR_INDEX: HashMap[address, HashMap[address, uint256]]
LP_INDEX  : HashMap[address, uint256]

@internal
def insert(new: PoolState) -> PoolState:
  self.POOL_STORE[new.id]                          = new
  self.PAIR_INDEX[new.base_token][new.quote_token] = new.id
  self.LP_INDEX[new.lp_token]                      = new.id
  return new

# Storage is initialized to zero.
@external
@view
def exists(id: uint256) -> bool:
  return self.POOL_STORE[id].id != 0

@external
@view
def exists_pair(base_token: address, quote_token: address) -> bool:
  return self.PAIR_INDEX[base_token][quote_token] != 0

@external
@view
def exists_lp(lp_token: address) -> bool:
  return self.LP_INDEX[lp_token] != 0

@external
@view
def lookup(id: uint256) -> PoolState:
  assert Pools(self).exists(id), ERR_PRECONDITIONS
  return self.POOL_STORE[id]

@external
@view
def lookup_pair(base_token: address, quote_token: address) -> PoolState:
  assert Pools(self).exists_pair(base_token, quote_token), ERR_PRECONDITIONS
  return self.POOL_STORE[self.PAIR_INDEX[base_token][quote_token]]

@external
@view
def lookup_lp(lp_token: address) -> PoolState:
  assert Pools(self).exists_lp(lp_token), ERR_PRECONDITIONS
  return self.POOL_STORE[self.LP_INDEX[lp_token]]

########################################################################
@external
def fresh(
  symbol     : String[65],
  base_token : address,
  quote_token: address,
  lp_token   : address) -> PoolState:
  self._INTERNAL()
  return self.insert(PoolState({
    id               : self.next_pool_id(),
    symbol           : symbol,
    base_token       : base_token,
    quote_token      : quote_token,
    lp_token         : lp_token,
    base_reserves    : 0,
    quote_reserves   : 0,
    base_interest    : 0,
    quote_interest   : 0,
    base_collateral  : 0,
    quote_collateral : 0,
  }))

########################################################################
@external
@view
def total_reserves(id: uint256) -> Tokens:
  ps: PoolState = Pools(self).lookup(id)
  return Tokens({base: ps.base_reserves, quote: ps.quote_reserves})

@external
@view
def unlocked_reserves(id: uint256) -> Tokens:
  ps: PoolState = Pools(self).lookup(id)
  return Tokens({
    base : ps.base_reserves  - ps.base_interest,
    quote: ps.quote_reserves - ps.quote_interest,
  })

########################################################################
@external
def mint(id: uint256, base_amt: uint256, quote_amt: uint256) -> PoolState:
  self._INTERNAL()
  ps: PoolState = Pools(self).lookup(id)
  return self.insert(PoolState({
    id               : ps.id,
    symbol           : ps.symbol,
    base_token       : ps.base_token,
    quote_token      : ps.quote_token,
    lp_token         : ps.lp_token,
    base_reserves    : ps.base_reserves  + base_amt,
    quote_reserves   : ps.quote_reserves + quote_amt,
    base_interest    : ps.base_interest,
    quote_interest   : ps.quote_interest,
    base_collateral  : ps.base_collateral,
    quote_collateral : ps.quote_collateral,
  }))


# LP tokens represent shares of the pool reserves.
# At a point in time (a given oracle price) we can compute three values:
#   - pool value pv, the value of the pool reserves expressed as quote tokens
#   - mint value mv, the value of the tokens provided by an LP expressed as quote tokens
#   - burn value bv, the value of the tokens returned to an LP expressed as quote tokens
# we compute the following functions:
#   mint: lp = mv/pv * total_lp_tokens
#   burn: bv = lp/total_lp_tokens * pv
# i.e. burn(mint(x)) = x
@external
@view
def calc_mint(
  id          : uint256,
  base_amt    : uint256,
  quote_amt   : uint256,
  total_supply: uint256,
  ctx         : Ctx) -> uint256:

  pv: uint256 = self.MATH.value(Pools(self).total_reserves(id), ctx).total_as_quote
  mv: uint256 = self.MATH.value(Tokens({base: base_amt, quote: quote_amt}), ctx).total_as_quote
  return Pools(self).f(mv, pv, total_supply)

@external
@pure
def f(mv: uint256, pv: uint256, ts: uint256) -> uint256:
  if ts == 0: return mv
  else      : return (mv * ts) / pv

@external
def burn(id: uint256, base_amt: uint256, quote_amt: uint256) -> PoolState:
  self._INTERNAL()
  ps: PoolState = Pools(self).lookup(id)
  return self.insert(PoolState({
    id               : ps.id,
    symbol           : ps.symbol,
    base_token       : ps.base_token,
    quote_token      : ps.quote_token,
    lp_token         : ps.lp_token,
    base_reserves    : ps.base_reserves  - base_amt,
    quote_reserves   : ps.quote_reserves - quote_amt,
    base_interest    : ps.base_interest,
    quote_interest   : ps.quote_interest,
    base_collateral  : ps.base_collateral,
    quote_collateral : ps.quote_collateral,
  }))

# Burning LP tokens is not always possible, since pools are fully-backed and
# a sufficient number of reserve tokens to pay out any open positions is locked
# at all times (all positions are guaranteed to close eventually due to fees).
@external
@view
def max_burn(id: uint256, total_supply: uint256, ctx: Ctx) -> uint256:
  """
  Return the maximum number of LP tokens which can currently be burned.
  """
  pv: uint256 = self.MATH.value(Pools(self).total_reserves(id),    ctx).total_as_quote
  uv: uint256 = self.MATH.value(Pools(self).unlocked_reserves(id), ctx).total_as_quote
  return (uv * total_supply) / pv - 1

@external
@view
def calc_burn(id: uint256, lp_amt: uint256, total_supply: uint256, ctx: Ctx) -> Tokens:
  pv      : uint256 = self.MATH.value(Pools(self).total_reserves(id), ctx).total_as_quote
  bv      : uint256 = self.g(lp_amt, total_supply, pv)
  unlocked: Tokens  = Pools(self).unlocked_reserves(id)
  value   : Value   = self.MATH.value(unlocked, ctx)
  uv      : uint256 = value.total_as_quote
  amts    : Tokens  = self.MATH.balanced(value, bv, ctx)
  assert uv         >= bv,             ERR_PRECONDITIONS
  assert amts.base  <= unlocked.base,  ERR_PRECONDITIONS
  assert amts.quote <= unlocked.quote, ERR_PRECONDITIONS
  return amts

@internal
@pure
def g(lp: uint256, ts: uint256, pv: uint256) -> uint256:
  return (lp * pv) / ts

########################################################################
@external
def open(id: uint256, collateral: Tokens, interest: Tokens) -> PoolState:
  """
  Update accounting to reflect a new position being opened.
  """
  self._INTERNAL()
  ps      : PoolState = Pools(self).lookup(id)
  reserves: Tokens    = Pools(self).unlocked_reserves(id)
  assert reserves.base  >= interest.base , ERR_PRECONDITIONS
  assert reserves.quote >= interest.quote, ERR_PRECONDITIONS
  return self.insert(PoolState({
    id               : ps.id,
    symbol           : ps.symbol,
    base_token       : ps.base_token,
    quote_token      : ps.quote_token,
    lp_token         : ps.lp_token,
    base_reserves    : ps.base_reserves,
    quote_reserves   : ps.quote_reserves,
    # lock reserves
    base_interest    : ps.base_interest    + interest.base,
    quote_interest   : ps.quote_interest   + interest.quote,
    base_collateral  : ps.base_collateral  + collateral.base,
    quote_collateral : ps.quote_collateral + collateral.quote,
  }))

########################################################################
@external
def close(id: uint256, d: Deltas) -> PoolState:
  """
  Apply transfers resulting from a position close to pool state.
  """
  self._INTERNAL()
  ps: PoolState = Pools(self).lookup(id)
  return self.insert(PoolState({
    id               : ps.id,
    symbol           : ps.symbol,
    base_token       : ps.base_token,
    quote_token      : ps.quote_token,
    lp_token         : ps.lp_token,
    base_reserves    : self.MATH.eval(ps.base_reserves,    d.base_reserves),
    quote_reserves   : self.MATH.eval(ps.quote_reserves,   d.quote_reserves),
    base_interest    : self.MATH.eval(ps.base_interest,    d.base_interest),
    quote_interest   : self.MATH.eval(ps.quote_interest,   d.quote_interest),
    base_collateral  : self.MATH.eval(ps.base_collateral,  d.base_collateral),
    quote_collateral : self.MATH.eval(ps.quote_collateral, d.quote_collateral),
  }))

# eof

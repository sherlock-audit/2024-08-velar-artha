########################################################################
import fees   as Fees #self
import math   as Math
import params as Params
import pools  as Pools

MATH     : public(Math)
PARAMS   : public(Params)
POOLS    : public(Pools)

CORE     : public(address)
POSITIONS: public(address)

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
  core     : address,
  positions: address):
  assert msg.sender == self.DEPLOYER, ERR_INVARIANTS
  assert not self.INITIALIZED       , ERR_INVARIANTS
  self.INITIALIZED = True

  self.MATH      = Math(math)
  self.PARAMS    = Params(params)
  self.POOLS     = Pools(pools)
  self.CORE      = core
  self.POSITIONS = positions

@internal
@view
def _INTERNAL():
  assert (msg.sender == self.CORE      or
          msg.sender == self.POSITIONS or
          msg.sender == self), ERR_PERMISSIONS

########################################################################
FEE_STORE   : HashMap[uint256, FeeState]
FEE_STORE_AT: HashMap[uint256, HashMap[uint256, FeeState]]

@external
@view
def lookup(id: uint256) -> FeeState:
  return self.FEE_STORE[id]

@external
@view
def fees_at_block(height: uint256, id: uint256) -> FeeState:
  return self.FEE_STORE_AT[height][id]

@internal
def insert(fs: FeeState) -> FeeState:
  # current/latest fee state
  self.FEE_STORE[fs.id] = fs
  # historical fee state
  self.FEE_STORE_AT[block.number][fs.id] = fs
  return fs

########################################################################
@external
def fresh(id: uint256) -> FeeState:
  self._INTERNAL()
  return self.insert(FeeState({
    id                   : id,
    t0                   : block.number,
    t1                   : block.number,
    borrowing_long       : 0,
    borrowing_short      : 0,
    funding_long         : 0,
    funding_short        : 0,
    long_collateral      : 0,
    short_collateral     : 0,
    borrowing_long_sum   : 0,
    borrowing_short_sum  : 0,
    funding_long_sum     : 0,
    funding_short_sum    : 0,
    received_long_sum    : 0,
    received_short_sum   : 0,
    }))

########################################################################
# rolling sums
@internal
@pure
def extend(X: uint256, x_m: uint256, m: uint256) -> uint256:
  """
  Extend a sum X for m blocks during which x_m has not changed.
  """
  return X + (m*x_m)

@internal
@pure
def slice(y_i: uint256, y_j: uint256) -> uint256:
  """
  Given x_0 + x_1 + ... + x_i-1 and x_0 + ... + x_i + ... + x_j-1, return
  x_i + ... + x_j-1
  """
  return y_j - y_i

# c.f. current_fees() below
# 10^27 = max 18 decimals and 10^9 units
ZEROS: constant(uint256) = 1000000000000000000000000000

@internal
@view
def apply(amount: uint256, fee: uint256) -> uint256:
  return self.MATH.apply(amount, fee).fee

@internal
@pure
def divide(paid: uint256, collateral: uint256) -> uint256:
  if collateral == 0: return 0
  else              : return (paid * ZEROS) / collateral

@internal
@pure
def multiply(ci: uint256, terms: uint256) -> uint256:
  return (ci * terms) / ZEROS

########################################################################
@external
def update(id: uint256) -> FeeState:
  self._INTERNAL()
  return self.insert(Fees(self).current_fees(id))

@external
@view
def current_fees(id: uint256) -> FeeState:
  """
  Update incremental fee state, called whenever the pool state changes.
  """
  # prev/last updated state
  fs       : FeeState  = Fees(self).lookup(id)
  # current state
  ps       : PoolState = self.POOLS.lookup(id)
  new_fees : DynFees   = self.PARAMS.dynamic_fees(ps)
  # number of blocks elapsed
  new_terms: uint256   = block.number - fs.t1

  # When we value a position, we need to calculate the total amount of
  # fee obligations that position has accumulated over its lifetime.
  # To do this incrementally, we proceed as follows:
  #
  # 1) Fee payments are local in the sense that they can be computed
  #    by looking at a single position:
  #    - the total amount of fees due for a position with collateral c
  #      which was opened at block N and closed at block M, where f_i is
  #      the fee at block i is:
  #      c * f_N + c * f_N+1 + ... + c * f_M-1 = c*(f_N + ... + f_M-1).
  #    - we store the sum(f_i) term here since c is static (up to and
  #      not including this block, since during a block the pool state,
  #      and hence the fees, may change)
  #    - we also store the current sample for the current block (the final
  #      update in a block will write the final fee value for that block)
  borrowing_long_sum  : uint256 = self.extend(fs.borrowing_long_sum,  fs.borrowing_long,  new_terms)
  borrowing_short_sum : uint256 = self.extend(fs.borrowing_short_sum, fs.borrowing_short, new_terms)
  funding_long_sum    : uint256 = self.extend(fs.funding_long_sum,    fs.funding_long,    new_terms)
  funding_short_sum   : uint256 = self.extend(fs.funding_short_sum,   fs.funding_short,   new_terms)

  # 2) Funding fee receipts are a little more complicated:
  #    - assume wlog that shorts are paying longs
  #    - let C_s_i = total short collateral at block i
  #          C_l_i = total long  collateral at block i
  #          c_j   = a single long position's collateral (sum(c_j) = C_l_i)
  #          f_i   = funding fee at block i
  #    - short positions in aggregate pay T_i = C_s_i * f_i in funding fees at block i
  #    - an individual long position receives a share of this total payment:
  #      c_j/C_l_i * T_i
  #    - notice that we don't know c_j here, so we store the fee payment per unit
  #      collateral instead (as an incremental sum as for borrowing fees)
  #
  # paid     = f_0 * C_l_0           + ... + f_i * C_l_i
  # received = f_0 * C_l_0 * 1/C_s_0 + ... + f_i * C_l_i * 1/C_s_i
  #
  # Notice that rounding errors (down) should be safe in the sense that paid >= received.
  paid_long_term      : uint256 = self.apply(fs.long_collateral, fs.funding_long * new_terms)
  received_short_term : uint256 = self.divide(paid_long_term,    fs.short_collateral)

  paid_short_term     : uint256 = self.apply(fs.short_collateral, fs.funding_short * new_terms)

  received_long_term  : uint256 = self.divide(paid_short_term,    fs.long_collateral)

  received_long_sum   : uint256 = self.extend(fs.received_long_sum,  received_long_term,  1)
  received_short_sum  : uint256 = self.extend(fs.received_short_sum, received_short_term, 1)

  if new_terms == 0:
    return FeeState({
    id                   : fs.id,
    t0                   : fs.t0,
    t1                   : fs.t1,
    # update samples
    borrowing_long       : new_fees.borrowing_long,
    borrowing_short      : new_fees.borrowing_short,
    funding_long         : new_fees.funding_long,
    funding_short        : new_fees.funding_short,
    long_collateral      : ps.quote_collateral,
    short_collateral     : ps.base_collateral,
    # no new terms
    borrowing_long_sum   : fs.borrowing_long_sum,
    borrowing_short_sum  : fs.borrowing_short_sum,
    funding_long_sum     : fs.funding_long_sum,
    funding_short_sum    : fs.funding_short_sum,
    received_long_sum    : fs.received_long_sum,
    received_short_sum   : fs.received_short_sum,
    })
  else:
    return FeeState({
    id                   : fs.id,
    t0                   : fs.t0,
    t1                   : block.number,
    # update samples
    borrowing_long       : new_fees.borrowing_long,
    borrowing_short      : new_fees.borrowing_short,
    funding_long         : new_fees.funding_long,
    funding_short        : new_fees.funding_short,
    long_collateral      : ps.quote_collateral,
    short_collateral     : ps.base_collateral,
    # update sums
    borrowing_long_sum   : borrowing_long_sum,
    borrowing_short_sum  : borrowing_short_sum,
    funding_long_sum     : funding_long_sum,
    funding_short_sum    : funding_short_sum,
    received_long_sum    : received_long_sum,
    received_short_sum   : received_short_sum,
    })

########################################################################
struct Period:
  borrowing_long : uint256
  borrowing_short: uint256
  funding_long   : uint256
  funding_short  : uint256
  received_long  : uint256
  received_short : uint256

@internal
@view
def query(id: uint256, opened_at: uint256) -> Period:
  """
  Return the total fees due from block `opened_at` to the current block.
  """
  fees_i : FeeState = Fees(self).fees_at_block(opened_at, id)
  fees_j : FeeState = Fees(self).current_fees(id)
  return Period({
    borrowing_long  : self.slice(fees_i.borrowing_long_sum,  fees_j.borrowing_long_sum),
    borrowing_short : self.slice(fees_i.borrowing_short_sum, fees_j.borrowing_short_sum),
    funding_long    : self.slice(fees_i.funding_long_sum,    fees_j.funding_long_sum),
    funding_short   : self.slice(fees_i.funding_short_sum,   fees_j.funding_short_sum),
    received_long   : self.slice(fees_i.received_long_sum,   fees_j.received_long_sum),
    received_short  : self.slice(fees_i.received_short_sum,  fees_j.received_short_sum),
  })

########################################################################
@external
@view
def calc(id: uint256, long: bool, collateral: uint256, opened_at: uint256) -> SumFees:
    period: Period  = self.query(id, opened_at)
    P_b   : uint256 = self.apply(collateral, period.borrowing_long) if long else (
                      self.apply(collateral, period.borrowing_short) )
    P_f   : uint256 = self.apply(collateral, period.funding_long) if long else (
                      self.apply(collateral, period.funding_short) )
    R_f   : uint256 = self.multiply(collateral, period.received_long) if long else (
                      self.multiply(collateral, period.received_short) )

    return SumFees({funding_paid: P_f, funding_received: R_f, borrowing_paid: P_b})

# eof

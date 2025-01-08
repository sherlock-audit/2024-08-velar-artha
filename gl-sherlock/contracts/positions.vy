########################################################################
import positions as Positions #self
import math      as Math
import params    as Params
import pools     as Pools
import fees      as Fees

MATH  : public(Math)
PARAMS: public(Params)
POOLS : public(Pools)
FEES  : public(Fees)

CORE : public(address)

DEPLOYER   : address
INITIALIZED: bool

@external
def __init__():
  self.DEPLOYER    = msg.sender
  self.INITIALIZED = False

@external
def __init__2(
  math  : address,
  params: address,
  pools : address,
  fees  : address,
  core  : address):
  assert msg.sender == self.DEPLOYER, ERR_INVARIANTS
  assert not self.INITIALIZED       , ERR_INVARIANTS
  self.INITIALIZED = True

  self.MATH        = Math(math)
  self.PARAMS      = Params(params)
  self.POOLS       = Pools(pools)
  self.FEES        = Fees(fees)
  self.CORE        = core
  self.POSITION_ID = 0

@internal
def _INTERNAL():
  assert (msg.sender == self.CORE or msg.sender == self), ERR_PERMISSIONS

########################################################################
POSITION_ID: uint256

@internal
def next_position_id() -> uint256:
  id : uint256 = self.POSITION_ID
  nxt: uint256 = id + 1
  self.POSITION_ID = nxt
  return nxt

@external
@view
def get_nr_positions() -> uint256:
  return self.POSITION_ID

########################################################################
POSITION_STORE: HashMap[uint256, PositionState]

@internal
def insert(new: PositionState) -> PositionState:
  self.POSITION_STORE[new.id] = new
  return new

@external
@view
def exists(id: uint256) -> bool:
  return self.POSITION_STORE[id].id != 0

@external
@view
def lookup(id: uint256) -> PositionState:
  assert Positions(self).exists(id), ERR_PRECONDITIONS
  return self.POSITION_STORE[id]

########################################################################
# UI helpers
MAX_POSITIONS : constant(uint256) = 500
USER_POSITIONS: HashMap[address, DynArray[uint256, 500]]

@internal
def insert_user_position(user: address, id: uint256) -> bool:
  # initialized to empty
  ids: DynArray[uint256, 500] = self.USER_POSITIONS[user]
  ids.append(id)
  self.USER_POSITIONS[user] = ids
  return True

@external
@view
def lookup_user_positions(user: address) -> DynArray[PositionState, 500]:
  ids: DynArray[uint256, 500] = self.USER_POSITIONS[user]
  res: DynArray[PositionState, 500] = []
  for id in ids:
    res.append(Positions(self).lookup(id))
  return res

@external
@view
def get_nr_user_positions(user: address) -> uint256:
  return len(self.USER_POSITIONS[user])

########################################################################
@external
def open(
  user      : address,
  pool      : uint256,
  long      : bool,
  collateral: uint256,
  leverage  : uint256,
  ctx       : Ctx) -> PositionState:
  self._INTERNAL()

  # Opening a position with leverage can be thought of as purchasing
  # an amplified number of tokens.
  # Longs buy base tokens with quote collateral and shorts buy quote
  # tokens with base collateral (alternatively, longs buy base and shorts
  # sell base).
  virtual_tokens: uint256 = self.MATH.quote_to_base(collateral, ctx) if long else (
                            self.MATH.base_to_quote(collateral, ctx) )
  interest      : uint256 = virtual_tokens * leverage

  pos: PositionState      = PositionState({
    id         : self.next_position_id(),
    pool       : pool,
    user       : user,
    status     : Status.OPEN,
    long       : long,
    collateral : collateral,
    leverage   : leverage,
    interest   : interest,
    entry_price: ctx.price,
    exit_price : 0,
    opened_at  : block.number,
    closed_at  : 0,

    collateral_tagged: Tokens({base: 0, quote: collateral}) if long else (
                       Tokens({base: collateral, quote: 0}) ),
    interest_tagged  : Tokens({base: interest, quote: 0}) if long else (
                       Tokens({base: 0, quote: interest}) ),
  })
  ps: PoolState = self.POOLS.lookup(pool)

  assert Positions(self).get_nr_user_positions(user) <= MAX_POSITIONS
  assert self.PARAMS.is_legal_position(ps, pos)

  self.insert_user_position(user, pos.id)
  return self.insert(pos)

########################################################################
@external
@view
def value(id: uint256, ctx: Ctx) -> PositionValue:
  """
  Value a position at a point in time (the current block).
  """
  pos   : PositionState = Positions(self).lookup(id)
  # All positions will eventually become liquidatable due to fees.
  fees  : FeesPaid      = Positions(self).calc_fees(id)
  pnl   : PnL           = Positions(self).calc_pnl(id, ctx, fees.remaining)
  # Accounting steps needed to close position at this time:
  # - reduce open interest
  # - take all collateral and move to reserves
  # - take payout from reserves and send to user
  # - take funding paid from reserves and add to opposite collateral
  # - take funding received from opposite collateral and send to user
  #
  # Borrowing fees are handled explicitly in value() but implicitly here
  # (part of collateral).
  #
  # The worst-case failure mode occurs when one or more positions have
  # not been liquidated and have accumulated a funding fee obligation
  # larger than available collateral.
  #
  # In this case
  # 1) all user payouts safe
  #    - when calculating interest, the worst case payout (initial
  #      collateral + worst case (from the pool PoV) profit) is set
  #      aside, so user positions can always be paid out
  #    - the funding received part of the user payout will be paid out
  #      first come first serve (some users may not receive funding payouts)
  # 2) pool reserves are safe
  #    - the pool will never pay out any tokens it is not supposed to
  # 3) the pool potentially loses profits
  #    - since we always prioritize users and up to all available
  #      tokens in the collateral bucket are used to pay funding received
  #      there are hypothetical scenarios where all collateral tokens
  #      are used to service funding payments
  #
  # Positions which go negative due to price fluctuations cost the pool
  # EV profits since the most it can make is available collateral.
  pool              : PoolState = self.POOLS.lookup(pos.pool)
  bc                : uint256   = pool.base_collateral
  qc                : uint256   = pool.quote_collateral

  deltas: Deltas        = Deltas({
    base_interest   : [self.MATH.MINUS(pos.interest)],
    quote_interest  : [],

    base_transfer   : [self.MATH.PLUS(pnl.payout),
                       # funding_received is capped at collateral and we
                       # already have those tokens
                       self.MATH.PLUS(fees.funding_received)],
    base_reserves   : [self.MATH.MINUS(pnl.payout)],
    base_collateral : [self.MATH.MINUS(fees.funding_received)], # ->

    quote_transfer  : [],
                      # in the worst case describe above, reserves
                      # dont change
    quote_reserves  : [self.MATH.PLUS(min(pos.collateral, qc)),
                       self.MATH.MINUS(fees.funding_paid)],
    quote_collateral: [self.MATH.PLUS(fees.funding_paid),
                       self.MATH.MINUS(min(pos.collateral, qc))],
  }) if pos.long else  Deltas({
    base_interest   : [],
    quote_interest  : [self.MATH.MINUS(pos.interest)],

    base_transfer   : [],
    base_reserves   : [self.MATH.PLUS(min(pos.collateral, bc)),
                       self.MATH.MINUS(fees.funding_paid)],
    base_collateral : [self.MATH.PLUS(fees.funding_paid), # <-
                       self.MATH.MINUS(min(pos.collateral, bc))],

    quote_transfer  : [self.MATH.PLUS(pnl.payout),
                       self.MATH.PLUS(fees.funding_received)],
    quote_reserves  : [self.MATH.MINUS(pnl.payout)],
    quote_collateral: [self.MATH.MINUS(fees.funding_received)],
  })

  return PositionValue({position: pos, fees: fees, pnl: pnl, deltas: deltas})

########################################################################
struct Val:
  remaining: uint256
  deducted : uint256

@internal
@pure
def deduct(x: uint256, y: uint256) -> Val:
  if x >= y: return Val({remaining: x - y, deducted: y})
  else     : return Val({remaining: 0,     deducted: x})

@external
@view
def calc_fees(id: uint256) -> FeesPaid:
  pos             : PositionState = Positions(self).lookup(id)
  pool            : PoolState     = self.POOLS.lookup(pos.pool)
  fees            : SumFees       = self.FEES.calc(
                                    pos.pool, pos.long, pos.collateral, pos.opened_at)
  c0              : uint256       = pos.collateral
  c1              : Val           = self.deduct(c0,           fees.funding_paid)
  c2              : Val           = self.deduct(c1.remaining, fees.borrowing_paid)
  # Funding fees prioritized over borrowing fees.
  avail_pay       : uint256       = pool.quote_collateral if pos.long else (
                                    pool.base_collateral )
  funding_paid    : uint256       = min(c1.deducted, avail_pay)
  # borrowing_paid is for informational purposes only, could also say
  # min(c2.deducted, avail_pay - funding_paid).
  borrowing_paid  : uint256       = c2.deducted
  # other users' bad positions do not affect liquidatability
  remaining       : uint256       = c2.remaining
  # When there are negative positions (liquidation bot failure):
  avail           : uint256       = pool.base_collateral if pos.long else (
                                    pool.quote_collateral )
  # 1) we penalize negative positions by setting their funding_received to zero
  funding_received: uint256       = 0 if remaining == 0 else (
    # 2) funding_received may add up to more than available collateral, and
    #    we will pay funding fees out on a first come first serve basis
                                    min(fees.funding_received, avail) )
  return FeesPaid({
    funding_paid          : funding_paid,
    funding_paid_want     : fees.funding_paid,
    funding_received      : funding_received,
    funding_received_want : fees.funding_received,
    borrowing_paid        : borrowing_paid,
    borrowing_paid_want   : fees.borrowing_paid,
    remaining             : remaining,
  })

########################################################################
@external
@view
def calc_pnl(id: uint256, ctx: Ctx, remaining: uint256) -> PnL:
  if Positions(self).lookup(id).long: return Positions(self).calc_pnl_long( id, ctx, remaining)
  else                              : return Positions(self).calc_pnl_short(id, ctx, remaining)

@external
@view
def calc_pnl_long(id: uint256, ctx: Ctx, remaining: uint256) -> PnL:
  pos    : PositionState = Positions(self).lookup(id)
  ctx0   : Ctx           = Ctx({price         : pos.entry_price,
                                base_decimals : ctx.base_decimals,
                                quote_decimals: ctx.quote_decimals})
  vtokens: uint256       = pos.interest
  val0   : uint256       = self.MATH.base_to_quote(vtokens, ctx0)
  val1   : uint256       = self.MATH.base_to_quote(vtokens, ctx)
  loss   : uint256       = val0 - val1 if val0 > val1 else 0
  profit : uint256       = val1 - val0 if val1 > val0 else 0
  # Positions whose collateral drops to zero due to fee obligations
  # are liquidated and don't receive a payout.
  final  : uint256       = 0 if remaining == 0 else (
                             0 if loss > remaining else (
                               remaining - loss if loss > 0 else (
                               remaining + profit ) ) )
  # Accounting in quote, payout in base.
  payout : uint256       = self.MATH.quote_to_base(final, ctx)
  assert payout <= pos.interest, ERR_INVARIANTS
  return PnL({
    loss     : loss,
    profit   : profit,
    # Used to determine liquidatability.
    # Could use final instead to account for positive pnl,
    # which would allow positions in profit to be kept open longer
    # but this lets us bound position lifetimes (which lets LPs estimate how
    # long reserves will be locked) and unless fees are very high shouldn't
    # make too much of a difference for users.
    remaining: final - profit if final > profit else final,
    payout   : payout,
  })

@external
@view
def calc_pnl_short(id: uint256, ctx: Ctx, remaining_as_base: uint256) -> PnL:
  pos      : PositionState = Positions(self).lookup(id)
  ctx0     : Ctx           = Ctx({price         : pos.entry_price,
                                  base_decimals : ctx.base_decimals,
                                  quote_decimals: ctx.quote_decimals})
  # Slightly different from long because short collateral is in base.
  vtokens  : uint256       = pos.leverage * pos.collateral
  val0     : uint256       = self.MATH.base_to_quote(vtokens, ctx0)
  val1     : uint256       = self.MATH.base_to_quote(vtokens, ctx)
  loss     : uint256       = val1 - val0 if val1 > val0 else 0
  profit   : uint256       = val0 - val1 if val0 > val1 else 0
  # Notice we value the remaining collateral at the _current_ price.
  # This will result in slightly (depending on leverage) lower payouts
  # for winning short positions, and slightly higher payouts for losing
  # short positions (makes shorts a little bit more of an insurance
  # product).
  remaining: uint256       = self.MATH.base_to_quote(remaining_as_base, ctx)
  final    : uint256       = 0 if remaining == 0 else (
                               0 if loss > remaining else (
                                 remaining - loss if loss > 0 else (
                                 remaining + profit ) ) )
  # accounting in quote, payout in quote.
  payout   : uint256 = final
  left     : uint256 = self.MATH.quote_to_base(0 if loss > remaining else remaining - loss, ctx)
  assert payout <= pos.interest, ERR_INVARIANTS
  return PnL({
    loss     : loss,
    profit   : profit,
    remaining: left,
    payout   : payout,
  })

########################################################################
@external
@view
def is_liquidatable(id: uint256, ctx: Ctx) -> bool:
  """
  Determines whether position `id` is liquidatable at `ctx.price`.
  """
  v: PositionValue = Positions(self).value(id, ctx)
  return self.PARAMS.is_liquidatable(v.position, v.pnl)

@external
@view
def status(id: uint256, ctx: Ctx) -> Status:
  if Positions(self).is_liquidatable(id, ctx): return Status.LIQUIDATABLE
  else                                       : return Positions(self).lookup(id).status

########################################################################
@external
def close(id: uint256, ctx: Ctx) -> PositionValue:
  self._INTERNAL()
  pos: PositionState = Positions(self).lookup(id)
  assert pos.status   == Status.OPEN  , ERR_PRECONDITIONS
  assert block.number  > pos.opened_at, ERR_PRECONDITIONS
  self.insert(PositionState({
    id         : pos.id,
    pool       : pos.pool,
    user       : pos.user,
    status     : Status.CLOSED,
    long       : pos.long,
    collateral : pos.collateral,
    leverage   : pos.leverage,
    interest   : pos.interest,
    entry_price: pos.entry_price,
    exit_price : ctx.price,
    opened_at  : pos.opened_at,
    closed_at  : block.number,

    collateral_tagged: pos.collateral_tagged,
    interest_tagged  : pos.interest_tagged,
  }))
  return Positions(self).value(id, ctx)

# eof

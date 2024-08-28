########################################################################
import math as Math #self

########################################################################
# x = lower(lift(x))

@internal
@pure
def lift(tokens: Tokens, ctx: Ctx) -> Tokens:
  """
  Converts tokens to the same precision (number of decimals).
  """
  bd   : uint256 = ctx.base_decimals
  qd   : uint256 = ctx.quote_decimals
  s    : bool    = bd >= qd
  n    : uint256 = bd - qd if s else qd - bd
  m    : uint256 = 10 ** n
  base : uint256 = tokens.base if s else tokens.base  * m
  quote: uint256 = tokens.quote * m if s else tokens.quote
  return Tokens({base: base, quote: quote})

@internal
@pure
def lower(tokens: Tokens, ctx: Ctx) -> Tokens:
  """
  Converts lifted tokens back to their original representation.
  """
  bd   : uint256 = ctx.base_decimals
  qd   : uint256 = ctx.quote_decimals
  s    : bool    = bd >= qd
  n    : uint256 = bd - qd if s else qd - bd
  m    : uint256 = 10 ** n
  base : uint256 = tokens.base if s else tokens.base  / m
  quote: uint256 = tokens.quote / m if s else tokens.quote
  return Tokens({base: base, quote: quote})

@internal
@pure
def one(ctx: Ctx) -> uint256:
  """
  Unit in the lifted representation for Ctx.
  """
  bd: uint256 = ctx.base_decimals
  qd: uint256 = ctx.quote_decimals
  s : bool    = bd >= qd
  return 10 ** bd if s else 10 ** qd

########################################################################
# amount = price/one * volume

@internal
@pure
def to_amount(price: uint256, volume: uint256, one1: uint256) -> uint256:
  """
  Converts unit price to value of volume at that price.
  """
  return (price * volume) / one1

@internal
@pure
def from_amount(amount: uint256, price: uint256, one1: uint256) -> uint256:
  """
  Returns volume implied by price.
  """
  return (amount * one1) / price

########################################################################
# base  = quote_to_base(base_to_quote(base))
# quote = base_to_quote(quote_to_base(quote))

@external
@pure
def base_to_quote(tokens: uint256, ctx: Ctx) -> uint256:
  lifted : Tokens  = self.lift(Tokens({base: tokens, quote: ctx.price}), ctx)
  amt0   : uint256 = self.to_amount(lifted.quote, lifted.base, self.one(ctx))
  lowered: Tokens  = self.lower(Tokens({base: 0, quote: amt0}), ctx)
  return lowered.quote

@external
@pure
def quote_to_base(tokens: uint256, ctx: Ctx) -> uint256:
  l1     : Tokens  = self.lift(Tokens({base: 0, quote: tokens}),    ctx)
  l2     : Tokens  = self.lift(Tokens({base: 0, quote: ctx.price}), ctx)
  vol0   : uint256 = self.from_amount(l1.quote, l2.quote, self.one(ctx))
  lowered: Tokens  = self.lower(Tokens({base: vol0, quote: 0}), ctx)
  return lowered.base

########################################################################
@external
@view
def value(tokens: Tokens, ctx: Ctx) -> Value:
  """
  Given a bag of tokens, computes various quantities we are interested in
  in one place.
  This should be @pure but has to be @view due to the Math(self) call.
  """
  base                  : uint256 = tokens.base
  quote                 : uint256 = tokens.quote
  base_as_quote         : uint256 = Math(self).base_to_quote(base, ctx)
  quote_as_base         : uint256 = Math(self).quote_to_base(quote, ctx)
  total_as_base         : uint256 = base + quote_as_base
  total_as_quote        : uint256 = quote + base_as_quote
  have_more_base        : bool    = base_as_quote > quote

  base_excess_as_base   : uint256 = base - quote_as_base if have_more_base else 0
  base_excess_as_quote  : uint256 = base_as_quote - quote if have_more_base else 0
  quote_excess_as_base  : uint256 = 0 if have_more_base else quote_as_base - base
  quote_excess_as_quote : uint256 = 0 if have_more_base else quote - base_as_quote

  return Value({
  base                  : base,
  quote                 : quote,
  base_as_quote         : base_as_quote,
  quote_as_base         : quote_as_base,
  total_as_base         : total_as_base,
  total_as_quote        : total_as_quote,
  have_more_base        : have_more_base,
  base_excess_as_base   : base_excess_as_base,
  base_excess_as_quote  : base_excess_as_quote,
  quote_excess_as_base  : quote_excess_as_base,
  quote_excess_as_quote : quote_excess_as_quote,
})

########################################################################
@external
@view
def balanced(state: Value, burn_value: uint256, ctx: Ctx) -> Tokens:
  """
  Given the current state of the pool reserves, returns a mix of tokens
  of total value burn_value which improves pool balance (we consider a
  pool balanced when te value of base reserves equals quote reserves).
  Note that if we have an imbalanced pool (which is not necessarily
  a bad thing), this means that LPs mostly get back the tokens they
  put in.
  The preconditions (burn_value <= reserves) for this must be
  checked at the call site!
  """
  if state.have_more_base:
    if state.base_excess_as_quote >= burn_value:
      return Tokens({base: Math(self).quote_to_base(burn_value, ctx), quote: 0})
    else:
      base1: uint256 = state.base_excess_as_base
      left : uint256 = burn_value - state.base_excess_as_quote
      quote: uint256 = left / 2
      base2: uint256 = Math(self).quote_to_base(quote, ctx)
      base : uint256 = base1 + base2
      return Tokens({base: base, quote: quote})
  else:
    if state.quote_excess_as_quote >= burn_value:
      return Tokens({base: 0, quote: burn_value})
    else:
      quote1: uint256 = state.quote_excess_as_quote
      left  : uint256 = burn_value - quote1
      quote2: uint256 = left / 2
      base  : uint256 = Math(self).quote_to_base(quote2, ctx)
      quote : uint256 = quote1 + quote2
      return Tokens({base: base, quote: quote})

########################################################################
# Magic number which depends on the smallest fee one wants to support
# and the blocktime (since fees are per block). See types.vy/Parameters
# for an example.
DENOM: constant(uint256) = 1_000_000_000

@external
@pure
def apply(x: uint256, numerator: uint256) -> Fee:
  """
  Fees are represented as numerator only, with the denominator defined
  here. This computes x*fee capped at x.
  """
  fee      : uint256 = (x * numerator) / DENOM
  remaining: uint256 = x - fee if fee <= x else 0
  fee_     : uint256 = fee     if fee <= x else x
  return Fee({x: x, fee: fee_, remaining: remaining})

########################################################################
@external
@pure
def PLUS(x: uint256)  -> Instr: return Instr({op: OP.ADD_, arg: x})
@external
@pure
def MINUS(x: uint256) -> Instr: return Instr({op: OP.SUB_, arg: x})
# No constructors for MUL and DIV because we don't currently use those.

@external
@pure
def eval(n: uint256, instrs: DynArray[Instr, 100]) -> uint256:
  """
  Very simple accumulator-based arithmetic DSL.
  """
  res: uint256 = n
  for instr in instrs:
    res = self.eval1(res, instr)
  return res

@internal
@pure
def eval1(n: uint256, instr: Instr) -> uint256:
  op : OP      = instr.op
  arg: uint256 = instr.arg
  res: uint256 = 0
  if   op == OP.ADD_ : res = n + arg
  elif op == OP.SUB_ : res = n - arg
  elif op == OP.MUL_ : res = n * arg
  elif op == OP.DIV_ : res = n / arg
  else               : raise "unknown_op"
  return res

# eof

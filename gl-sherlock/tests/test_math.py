import ape
from hypothesis import strategies as st

# math.vy

# helpers

def tokens(b, q):
    return {'base': b, 'quote': q}

def ctx(p, bd, qd):
    return {'price': p, 'base_decimals': bd, 'quote_decimals': qd}

def state(b, q, price):
    moreBase = b > (q / price)
    return {
        'base'                 : b,
        'quote'                : q,
        'base_as_quote'        : b * price,
        'quote_as_base'        : int(q / price),
        'total_as_base'        : int(b + q / price),
        'total_as_quote'       : q + b * price,
        'have_more_base'       : moreBase,
        'base_excess_as_base'  : int(b - q / price) if moreBase else 0,
        'base_excess_as_quote' : b * price - q if moreBase else 0,
        'quote_excess_as_base' : 0 if moreBase else int(q / price - b),
        'quote_excess_as_quote': 0 if moreBase else q - b * price,
    }

def d(n): return n*10**6

# test

def test_base_to_quote(math):
    assert math.base_to_quote(100, ctx(1, 0, 0)) == 100
    assert math.base_to_quote(100, ctx(5, 0, 0)) == 500
    assert math.base_to_quote(100, ctx(500, 0, 0)) == 50_000
    assert math.base_to_quote(100_000_000, ctx(5_000_000, 6, 6)) == 500_000_000
    assert math.base_to_quote(100_000_000, ctx(500_000_000, 6, 8)) == 50_000_000_000

def test_quote_to_base(math):
    assert math.quote_to_base(100, ctx(1, 0, 0)) == 100
    assert math.quote_to_base(100, ctx(5, 0, 0)) == 20
    assert math.quote_to_base(100, ctx(500, 0, 0)) == 0
    assert math.quote_to_base(100_000_000, ctx(5_000_000, 6, 6)) == 20_000_000
    assert math.quote_to_base(100_000_000, ctx(500_000_000, 6, 8)) == 200_000

def test_value(math):
    # base > quote
    res = math.value(tokens(1000, 10_000), ctx(500, 0, 0))
    assert res == {
        'base'                  : 1000,
        'quote'                 : 10_000,
        'base_as_quote'         : 500_000,
        'quote_as_base'         : 20,
        'total_as_base'         : 1020,
        'total_as_quote'        : 510_000,
        'have_more_base'        : True,
        'base_excess_as_base'   : 980,
        'base_excess_as_quote'  : 490_000,
        'quote_excess_as_base'  : 0,
        'quote_excess_as_quote' : 0,
    }

    # quote > base
    res = math.value(tokens(1000, 100_000), ctx(20, 0, 0))
    assert res == {
        'base'                  : 1000,
        'quote'                 : 100_000,
        'base_as_quote'         : 20_000,
        'quote_as_base'         : 5000,
        'total_as_base'         : 6000,
        'total_as_quote'        : 120_000,
        'have_more_base'        : False,
        'base_excess_as_base'   : 0,
        'base_excess_as_quote'  : 0,
        'quote_excess_as_base'  : 4000,
        'quote_excess_as_quote' : 80_000,
    }

def test_balanced_same_price(math):
    state0 = state(10_000, 10_000, 1)
    res = math.balanced(state0, 200, ctx(1, 0, 0))
    assert res == {
        'base'  : 100,
        'quote' : 100,
    }, "equal amount when price is 1 and reserves balanced"

    # quote > base
    state0 = state(5000, 10_000, 1)
    res = math.balanced(state0, 200, ctx(1, 0, 0))
    assert res == {
        'base'  : 0,
        'quote' : 200,
    }, "paid in quote when quote > base and quote excess > burn value"

    # base > quote
    state0 = state(10_000, 5_000, 1)
    res = math.balanced(state0, 200, ctx(1, 0, 0))
    assert res == {
        'base'  : 200,
        'quote' : 0,
    }, "paid in base when base > quote and base excess > burn value"

    # NOTE: can return values > reserves
    state0 = state(10_000, 5_000, 1)
    assert state0['base_excess_as_base'] == 5000
    res = math.balanced(state0, 10000, ctx(1, 0, 0))
    assert res == {
        'base'  : 7500,
        'quote' : 2500,
    }, "paid in base when base > quote and burn value > excess base"

def test_balanced(math):
    # quote > base
    state0 = state(1_000, 1_000_000, 500)
    res = math.balanced(state0, 1000, ctx(500, 0, 0))
    assert res == {
        'base'  : 0,
        'quote' : 1000,
    }, "burn amount < excess quote"

    # base > quote
    state0 = state(1000, 10_000, 500)
    res = math.balanced(state0, 200, ctx(500, 0, 0))
    assert res == {
        'base'  : 0,
        'quote' : 0,
    }, "burn amount < 1 base"

    state0 = state(1000, 10_000, 500)
    res = math.balanced(state0, 1000, ctx(500, 0, 0))
    assert res == {
        'base'  : 2,
        'quote' : 0,
    }, "burn amount > 1 base"

def test_apply(math):
    assert math.apply(             0,              0)     == { 'x':              0, 'fee':             0, 'remaining':             0 }
    assert math.apply(   100_000_000, 10_000_000_000)     == { 'x':    100_000_000, 'fee':   100_000_000, 'remaining':             0 }
    assert math.apply(10_000_000_000,    100_000_000)     == { 'x': 10_000_000_000, 'fee': 1_000_000_000, 'remaining': 9_000_000_000 }
    assert math.apply(   100_000_000,         10_000)     == { 'x':    100_000_000, 'fee':          1000, 'remaining':    99_999_000 }
    assert math.apply( 2_000_000_000,         10_000).fee == 20_000

def plus(x):  return { 'op': 1, 'arg': x }
def minus(x): return { 'op': 2, 'arg': x }
def mul(x):   return { 'op': 4, 'arg': x }
def div(x):   return { 'op': 8, 'arg': x }

def test_ops(math):
    assert math.MINUS(20) == { 'op': 2, 'arg': 20 }
    assert math.PLUS(20)  == { 'op': 1, 'arg': 20 }

def test_eval(math):
    assert math.eval(0,   [plus(10)])  == 10
    assert math.eval(100, [minus(50)]) == 50
    assert math.eval(10,  [mul(2)])    == 20
    assert math.eval(10,  [div(2)])    == 5

    assert math.eval(0, [plus(10), mul(10)])                   == 100
    assert math.eval(0, [mul(10), plus(10)])                   == 10
    assert math.eval(0, [plus(10), plus(10), plus(2)])         == 22
    assert math.eval(0, [plus(10), mul(10), div(2), minus(2)]) == 48

    with ape.reverts("unknown_op"):
        math.eval(0, [{ 'op': 3, 'arg': 10}])


from ape import reverts
import pytest
from hypothesis import strategies as st

# helpers

def ctx(p, bd=6, qd=6):
    return {'price': p, 'base_decimals': bd, 'quote_decimals': qd}

def d(x): return x * 10**6

# fixtures

@pytest.fixture
def setup(core, api, oracle, pools, positions, fees,
          owner, lp_provider, VEL, STX, LP):
    def setup():
      core.fresh("VEL-STX", VEL, STX, LP, sender=owner)
      VEL.transfer(lp_provider, d(100_000), sender=owner)
      STX.transfer(lp_provider, d(100_000), sender=owner)
      VEL.approve(core.address, d(100_000), sender=lp_provider)
      STX.approve(core.address, d(100_000), sender=lp_provider)
    return setup

# test

def test_nr_pools(pools):
    assert pools.get_nr_pools() == 0

def test_exists_before_creation(pools, accounts):
    assert pools.exists(0) == False
    assert pools.exists(1) == False
    assert pools.exists_lp(accounts[1]) == False
    assert pools.exists_pair(accounts[1], accounts[2]) == False
    with reverts("PRECONDITIONS"):
        pools.lookup(1)
        pools.lookup_lp(accounts[1])

def test_f(pools):
    assert pools.f(0, 0, 0) == 0, "f(0,0,0)"
    assert pools.f(1, 1, 1) == 1, "f(1,1,1)"
    assert pools.f(2, 1, 1) == 2, "f(2,1,1)"
    assert pools.f(2, 1, 2) == 4, "f(2,1,2)"
    assert pools.f(500_000_000, 100_000_000, 2_000_000_000) == 10_000_000_000

def test_calc_mint_zero_supply(setup, pools):
    setup()
    # returns mv = (b * p + q)
    assert pools.calc_mint(1, 1_000_000, 0        , 0, ctx(d(5))) == 5_000_000
    assert pools.calc_mint(1, 1_000_000, 1_000_000, 0, ctx(d(5))) == 6_000_000
    assert pools.calc_mint(1, 0        , 1_000_000, 0, ctx(d(5))) == 1_000_000

@pytest.mark.parametrize("b,q,p", [
    (7076, 1, 81467037),
    (286137089, 7076, 1),
    (99, 14185, 19934),
    ])
def test_failed_flaky(setup, pools, b, q, p):
    setup()
    ID = 1
    TOTAL_SUPPLY = 0
    bd=6
    qd=6

    P = p * 10**qd
    B = b * 10**bd
    Q = q * 10**qd
    R = (B * P)//10**6 + Q
    assert pools.calc_mint(ID, B, Q, TOTAL_SUPPLY, ctx(P, bd, qd)) == R
    assert pools.calc_mint(ID, B, Q, TOTAL_SUPPLY, ctx(P, bd, qd)) == R

def test_calc_mint(setup, core, pools, mint, lp_provider, VEL, STX, LP):
    setup()
    ID = 1
    # can't just set total_supply, current pool reserves need be > 0
    mint(VEL, STX, LP, d(100), d(500), price=d(5), sender=lp_provider)
    assert LP.totalSupply() == 1_000_000_000, "LP before"

    assert pools.calc_mint(ID, d(1)  , 0     , d(1000), ctx(d(5))) == 5_000_000     , "calc_mint(1, 0, 1000)"
    assert pools.calc_mint(ID, d(1)  , d(1)  , d(1000), ctx(d(5))) == 6_000_000     , "calc_mint(1, 1, 1000)"
    assert pools.calc_mint(ID, 0     , d(1)  , d(1000), ctx(d(5))) == 1_000_000     , "calc_mint(0, 1, 1000)"
    assert pools.calc_mint(ID, d(100), d(500), d(1000), ctx(d(5))) == 1_000_000_000 , "calc_mint(100, 500, 1000)"

def test_calc_burn_no_reserves(setup, pools):
    setup()
    assert pools.calc_burn(1, 1_000_000, 100_000_000, ctx(d(5))) == {'base'  : 0, 'quote' : 0}

def test_calc_burn(setup, core, mint, pools, lp_provider, VEL, STX, LP):
    setup()
    tx = mint(VEL, STX, LP, d(100), d(500), price=d(5), sender=lp_provider)
    assert not tx.failed
    assert pools.calc_burn(1, d(1)  , d(100), ctx(d(5)))    == {'base': d(1)  , 'quote': d(5)}
    assert pools.calc_burn(1, d(100), d(100), ctx(d(5)))    == {'base': d(100), 'quote': d(500)}
    assert pools.calc_burn(1, d(100), d(100), ctx(d(100)))  == {'base': d(100), 'quote': d(500)}


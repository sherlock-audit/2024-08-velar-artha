from ape import reverts
import pytest
from conftest import ctx, d
from enum import Enum

# helpers

class Status(Enum):
    OPEN = 1
    CLOSED = 2
    LIQUIDATABLE = 4

# fixtures

@pytest.fixture
def setup(core, api, oracle, pools, positions, fees,
          mint,
          owner, lp_provider, long, short,
          VEL, STX, LP, mint_token):
    def setup():

      pools.CORE()      == core
      fees.CORE()       == core
      positions.CORE()  == core
      oracle.API()      == api
      core.API()        == api

      core.fresh("VEL-STX", VEL, STX, LP, sender=owner)
      mint_token(VEL, d(100_000), lp_provider)
      mint_token(STX, d(100_000), lp_provider)
      mint_token(VEL, d(10_000) , long)
      mint_token(STX, d(10_000) , long)
      mint_token(VEL, d(10_000) , short)
      mint_token(STX, d(10_000) , short)
      assert not VEL.approve(core.address, d(100_000), sender=lp_provider).failed
      STX.approve(core.address, d(100_000), sender=lp_provider)
      VEL.approve(core.address, d(10_000) , sender=long)
      STX.approve(core.address, d(10_000) , sender=long)
      VEL.approve(core.address, d(10_000) , sender=short)
      STX.approve(core.address, d(10_000) , sender=short)
      mint(VEL, STX, LP, d(10_000), d(50_000), price=d(5), sender=lp_provider)
    return setup

# test

def test_lookups_initial(positions, long, owner):
    assert positions.get_nr_positions(sender=owner) == 0
    assert positions.exists(1, sender=owner)        == False
    assert positions.lookup_user_positions(long, sender=owner) == []
    with reverts("PRECONDITIONS"):
        positions.lookup(1, sender=owner)

def test_lookups(setup, positions, params, pools, open, long, VEL, STX):
    assert positions.get_nr_positions() == 0
    assert positions.exists(1) == False
    assert len(positions.lookup_user_positions(long)) == 0
    setup()
    open(VEL, STX, True, d(2), 2, price=d(5), sender=long)

    assert positions.get_nr_positions() == 1
    assert len(positions.lookup_user_positions(long)) == 1

def test_calc_pnl(setup, positions, params, pools, open, VEL, STX, long):
    setup()

    ENTRY_PRICE = d(5)
    tx = open(VEL, STX, True, d(2), 10, price=ENTRY_PRICE, sender=long)
    assert not tx.failed

    remaining = positions.calc_fees(1, sender=long)['remaining']

    res = positions.calc_pnl(1, ctx(ENTRY_PRICE), remaining, sender=long)
    assert res == {
        'loss'     : 0,
        'profit'   : 0,
        'remaining': remaining,
        'payout'   : remaining * d(1) // ENTRY_PRICE ,
    }

    # loss
    res = positions.calc_pnl(1, ctx(d(4)), remaining, sender=long)
    print(res)
    assert res == {
        'loss'     : 3_996_000,     # 1/5 * interest (10xC)
        'profit'   : 0,
        'remaining': 0,
        'payout'   : 0,
    }

    # profit
    res = positions.calc_pnl(1, ctx(d(6)), remaining, sender=long)
    print(res)
    assert res == {
        'loss'     : 0,
        'profit'   : 3_996_000,
        'remaining': remaining,
        'payout'   : (remaining + 3_996_000) * d(1) // d(6),
    }

def test_is_liquidatable(setup, positions, open, VEL, STX, long):
    setup()

    ENTRY_PRICE = d(5)
    tx = open(VEL, STX, True, d(2), 10, price=ENTRY_PRICE, sender=long)
    assert not tx.failed

    tx = positions.is_liquidatable(1, ctx(ENTRY_PRICE), sender=long)
    assert tx == False

    tx = positions.is_liquidatable(1, ctx(3), sender=long)
    assert tx == True

def test_status(setup, positions, open, VEL, STX, owner, long):
    setup()
    tx = open(VEL, STX, True, d(2), 10, price=d(5), sender=long)
    assert not tx.failed

    tx = positions.status(1, ctx(d(5)), sender=owner)
    assert tx == Status.OPEN.value

    tx = positions.status(1, ctx(3), sender=owner)
    assert tx == Status.LIQUIDATABLE.value

def test_value(setup, positions, open, VEL, STX, owner, long):
    setup()
    tx = open(VEL, STX, True, d(2), 10, price=d(5), sender=long)
    assert not tx.failed

    tx = positions.value(1, ctx(d(5)), sender=owner)
    assert tx.fees == {
        'funding_paid'         : 0,
        'funding_paid_want'    : 0,
        'funding_received'     : 0,
        'funding_received_want': 0,
        'borrowing_paid'       : 0,
        'borrowing_paid_want'  : 0,
        'remaining'            : 1998000
    }

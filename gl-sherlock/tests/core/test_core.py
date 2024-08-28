import ape
from ape import chain
import pytest
from conftest import d
import re

ERR_PERMISSIONS   = re.compile("PERMISSIONS")
ERR_INVARIANTS    = re.compile("INVARIANTS")
ERR_PRECONDITIONS = re.compile("PRECONDITIONS")

# fixtures

@pytest.fixture
def setup(core, api, oracle, pools, positions, fees,
                mint,
                owner, lp_provider, long, short, VEL, STX, LP, mint_token):
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
      VEL.approve(core.address, d(100_000), sender=lp_provider)
      STX.approve(core.address, d(100_000), sender=lp_provider)
      VEL.approve(core.address, d(10_000) , sender=long)
      STX.approve(core.address, d(10_000) , sender=long)
      VEL.approve(core.address, d(10_000) , sender=short)
      STX.approve(core.address, d(10_000) , sender=short)
      mint(VEL, STX, LP, d(10_000), d(50_000), price=d(5), sender=lp_provider)
    return setup


# test

def test_init(core, api, oracle, extractor, math, params, pools, fees, positions, owner):
    assert core.MATH()      == math
    assert core.PARAMS()    == params
    assert core.POOLS()     == pools
    assert core.FEES()      == fees
    assert core.POSITIONS() == positions
    assert core.API()       == api
    assert core.COLLECTOR() == owner

    assert oracle.API()       == api
    assert oracle.EXTRACTOR() == extractor
    feed = oracle.FEED_ID()
    assert feed.rstrip(b"\x00") == b"BTC"

def test_create(core,
                api, oracle, pools, positions, fees,
                owner, long,
                VEL, STX, USD, LP):

    with ape.reverts(ERR_PERMISSIONS):
        core.fresh("VEL-STX", VEL, STX, LP, sender=long)         # not owner

    tx = core.fresh("VEL-STX", VEL, STX, LP, sender=owner)
    assert not tx.failed

    logs = core.Create.from_receipt(tx)
    assert logs[0].user == owner
    assert logs[0].pool == 1

    # TODO: obsolete now
    with ape.reverts(ERR_PRECONDITIONS):
        core.fresh("VEL-STX", STX, VEL, LP, sender=owner)       # base/quote pair exists
        core.fresh("USD-STX", USD, STX, LP, sender=owner)       # lp-token already used

def test_mint(core,
              api, oracle, pools, positions, fees,
              mint,
              owner, lp_provider,
              VEL, STX, USD, LP, LP2, mint_token):

    tx = core.fresh("VEL-STX", VEL, STX, LP, sender=owner)
    assert not tx.failed
    tx = mint_token(VEL, 10_000_000_000, lp_provider)
    assert not tx.failed
    tx = mint_token(STX, 10_000_000_000, lp_provider)
    assert not tx.failed

    VEL.approve(core.address, d(10_000), sender=lp_provider)
    STX.approve(core.address, d(10_000), sender=lp_provider)
    assert VEL.allowance(lp_provider, core) == d(10_000)
    assert STX.allowance(lp_provider, core) == d(10_000)

    with ape.reverts(ERR_PRECONDITIONS):
        mint(STX, VEL, LP , d(100), d(500), price=d(5), sender=lp_provider)    # wrong token
        mint(VEL, USD, LP , d(100), d(500), price=d(5), sender=lp_provider)
        mint(VEL, STX, LP2, d(100), d(500), price=d(5), sender=lp_provider)
        mint(VEL, STX, LP, 0, 0 , price=d(5), sender=lp_provider)              # amt 0
        mint(VEL, STX, LP, 0, d(100), price=d(5), sender=lp_provider)

    tx = mint(VEL, STX, LP, d(100), d(500), price=d(5), sender=lp_provider)
    assert not tx.failed

    logs = core.Mint.from_receipt(tx)
    assert logs[0].user         == lp_provider
    assert logs[0].total_supply == 0          # before
    assert logs[0].lp_amt       == 1_000_000_000
    assert logs[0].base_amt     == 100_000_000
    assert logs[0].quote_amt    == 500_000_000


def test_burn(core,
              api, oracle, pools, positions, fees,
              mint, burn,
              owner, lp_provider,
              VEL, STX, USD, LP, LP2, mint_token):

    tx = core.fresh("VEL-STX", VEL, STX, LP, sender=owner)
    assert not tx.failed
    logs = core.Create.from_receipt(tx)
    assert logs[0].pool == 1
    tx = mint_token(VEL, 10_000_000_000, lp_provider)
    tx = mint_token(STX, 10_000_000_000, lp_provider)
    VEL.approve(core.address, d(10_000), sender=lp_provider)
    STX.approve(core.address, d(10_000), sender=lp_provider)

    tx = mint(VEL, STX, LP, d(100), d(500), price=d(5), sender=lp_provider)
    assert not tx.failed

    with ape.reverts(ERR_PRECONDITIONS):
        burn(STX, VEL, LP , d(100), price=d(5), sender=lp_provider)   # wrong token
        burn(VEL, USD, LP , d(100), price=d(5), sender=lp_provider)
        burn(VEL, STX, LP2, d(100), price=d(5), sender=lp_provider)
        burn(VEL, STX, LP , 0     , price=d(5), sender=lp_provider)   # amt 0

    tx = burn(VEL, STX, LP, d(100), price=d(5), sender=lp_provider)
    assert not tx.failed
    logs = core.Burn.from_receipt(tx)
    print(logs)
    assert logs[0].user         == lp_provider
    # assert logs[0].pool         == [1, "VEL-STX", ...]
    assert logs[0].total_supply == 1_000_000_000          # before
    assert logs[0].lp_amt       == 100_000_000
    assert logs[0].base_amt     == 10_000_000
    assert logs[0].quote_amt    == 50_000_000


def test_open(setup, core,
              open,
              long, short,
              VEL, STX, USD):

    setup()

    with ape.reverts(ERR_PRECONDITIONS):
        open(STX, VEL, True, d(2), 1, price=d(5), sender=long)    # wrong token
        open(VEL, USD, True, d(2), 1, price=d(5), sender=long)
        open(VEL, STX, True, 0   , 1, price=d(5), sender=long)    # amt 0
        open(VEL, STX, True, 1   , 0, price=d(5), sender=long)

    # long position
    tx = open(VEL, STX, True, d(2), 1, price=d(5), sender=long)
    assert not tx.failed
    logs = core.Open.from_receipt(tx)
    assert logs[0].position[2]        == long
    assert logs[0].position[3]        == 1             # status
    assert logs[0].position[5]        == 1_998_000     # collateral
    assert logs[0].position[7]        == 399_600       # interest
    assert logs[0].position[8]        == 5_000_000
    assert logs[0].position[9]        == 0
    assert logs[0].position[10]       == 37            # opened-at
    assert logs[0].position[11]       == 0
    assert logs[0].position[12][0]    == 0
    assert logs[0].position[12][1]    == 1_998_000
    assert logs[0].position[13][0]    == 399_600
    assert logs[0].position[13][1]    == 0

    # fee = d(2) / 1000 // 0.1%
    fee = d(2) / 1000
    assert VEL.balanceOf(long)          == 10_000_000_000
    assert STX.balanceOf(long)          == 10_000_000_000 - 2_000_000
    assert VEL.balanceOf(core.address)  == 10_000_000_000
    assert STX.balanceOf(core.address)  == 50_000_000_000 + 2_000_000 - fee

    # short position
    tx = open(VEL, STX, False, d(2), 1, price=d(5), sender=short)
    assert not tx.failed
    logs = core.Open.from_receipt(tx)
    assert logs[0].position[2]        == short
    assert logs[0].position[3]        == 1             # status
    assert logs[0].position[4]        == False         # long
    assert logs[0].position[5]        == 1_998_000     # collateral
    assert logs[0].position[7]        == 9_990_000     # interest
    assert logs[0].position[8]        == 5_000_000
    assert logs[0].position[9]        == 0
    assert logs[0].position[10]       == 38            # opened-at
    assert logs[0].position[11]       == 0
    assert logs[0].position[12][0]    == 1_998_000
    assert logs[0].position[12][1]    == 0
    assert logs[0].position[13][0]    == 0
    assert logs[0].position[13][1]    == 9_990_000

    fee = d(2) / 1000
    assert VEL.balanceOf(short)         == 10_000_000_000 - 2_000_000
    assert STX.balanceOf(short)         == 10_000_000_000
    assert VEL.balanceOf(core.address)  == 10_000_000_000 + 2_000_000 - fee
    assert STX.balanceOf(core.address)  == 50_001_998_000

def test_close_preconditions(setup,
                             open, close,
                             long, short,
                             VEL, STX, USD):
    setup()

    open(VEL, STX, True, d(2), 2, price=d(5), sender=long)

    with ape.reverts(ERR_PRECONDITIONS):
        close(STX, VEL, 1, price=d(5), sender=long)     # wrong token
        close(VEL, USD, 1, price=d(5), sender=long)
        close(VEL, STX, 1, price=d(5), sender=short)    # wrong user


def test_close_long(setup, core,
                    open, close,
                    long,
                    VEL, STX):
    setup()

    tx = open(VEL, STX, True, d(10), 2, price=d(5), sender=long)
    chain.mine(10_000)

    tx = close(VEL, STX, 1, price=d(5), sender=long)
    assert not tx.failed
    logs = core.Close.from_receipt(tx)
    fee = 10_000
    assert logs[0].value[1]             == [0, 0, 0, 0, 99, 99, 9989901]       # FeesPaid
    assert logs[0].value[2]             == [0, 0, 9989901, 1997980]            # [loss, profit, remaining, payout]
    assert VEL.balanceOf(long)          == 10_000_000_000 + 1997980
    assert STX.balanceOf(long)          == 10_000_000_000 - 10_000_000
    assert VEL.balanceOf(core.address)  == 10_000_000_000 - 1997980
    assert STX.balanceOf(core.address)  == 50_000_000_000 + 10_000_000 - fee

def test_close_short(setup, core, oracle,
                     open, close,
                     short,
                     VEL, STX):
    setup()
    oracle.API()

    tx = open(VEL, STX, False, d(10), 2, price=d(5), sender=short)
    chain.mine(10_000)

    tx = close(VEL, STX, 1, price=d(5), sender=short)
    assert not tx.failed
    logs = core.Close.from_receipt(tx)
    fee = 10_000
    payout_as_base = 9989901 * 5
    assert logs[0].value[1]             == [0, 0, 0, 0, 99, 99, 9989901]                # FeesPaid
    assert logs[0].value[2]             == [0, 0, 9989901, payout_as_base]              # [loss, profit, remaining, payout]
    assert VEL.balanceOf(short)         == 10_000_000_000 - 10_000_000
    assert STX.balanceOf(short)         == 10_000_000_000 + payout_as_base
    assert VEL.balanceOf(core.address)  == 10_000_000_000 + 10_000_000  - fee
    assert STX.balanceOf(core.address)  == 50_000_000_000 - payout_as_base

def test_close_long_profit(setup, core,
                           open, close,
                           long,
                           VEL, STX):
    setup()

    tx = open(VEL, STX, True, d(10), 2, price=d(5), sender=long)
    chain.mine(10_000)

    tx = close(VEL, STX, 1, price=d(6), sender=long)
    assert not tx.failed
    logs = core.Close.from_receipt(tx)
    assert logs[0].value[1][6]          == 9989901
    assert logs[0].value[1]             == [0, 0, 0, 0, 99, 99, 9989901]         # FeesPaid
    # payout = 3996000 + 9989901 / new_price
    assert logs[0].value[2]             == [0, 3996000, 9989901, 2330983]        # [loss, profit, remaining, payout]
    assert VEL.balanceOf(long)          == 10_000_000_000 + 2330983
    assert STX.balanceOf(long)          == 10_000_000_000 - 10_000_000
    assert VEL.balanceOf(core.address)  == 10_000_000_000 - 2330983
    assert STX.balanceOf(core.address)  == 50_000_000_000 + 10_000_000 - 10_000

def test_close_short_profit(setup, core,
                            open, close,
                            short, VEL, STX):
    setup()

    tx = open(VEL, STX, False, d(10), 2, price=d(5), sender=short)
    chain.mine(10_000)

    tx = close(VEL, STX, 1, price=d(4), sender=short)
    assert not tx.failed
    logs = core.Close.from_receipt(tx)

    C = 10_000_000 - 10_000
    leverage = 2
    p0 = 5
    p1 = 4
    remaining = 9989901
    # payout = remaining * p1 + (p0 - p1)(collateral * leverage)
    profit = (p0 - p1) * (C * leverage)
    payout_as_base = remaining * p1 + profit
    assert logs[0].value[1]             == [0, 0, 0, 0, 99, 99, 9989901]              # FeesPaid
    assert logs[0].value[2]             == [0, profit, 9989901, payout_as_base]       # [loss, profit, remaining, payout]
    assert VEL.balanceOf(short)         == 10_000_000_000 - 10_000_000
    assert STX.balanceOf(short)         == 10_000_000_000 + payout_as_base
    assert VEL.balanceOf(core.address)  == 10_000_000_000 + 10_000_000 - 10_000
    assert STX.balanceOf(core.address)  == 50_000_000_000 - payout_as_base

def test_close_long_loss(setup, core,
                         open, close,
                         long,
                         VEL, STX):
    setup()

    tx = open(VEL, STX, True, d(10), 2, price=d(5), sender=long)
    chain.mine(10_000)

    tx = close(VEL, STX, 1, price=d(4), sender=long)
    logs = core.Close.from_receipt(tx)
    fee = 10_000
    # payout = 9989901 - 3996000 / p1
    assert logs[0].value[1]             == [0, 0, 0, 0, 99, 99, 9989901]
    assert logs[0].value[2]             == [3996000, 0, 5993901, 1498475]         # [loss, profit, remaining, payout]
    assert VEL.balanceOf(long)          == 10_000_000_000 + 1498475
    assert STX.balanceOf(long)          == 10_000_000_000 - 10_000_000
    assert VEL.balanceOf(core.address)  == 10_000_000_000 - 1498475
    assert STX.balanceOf(core.address)  == 50_000_000_000 + 10_000_000 - fee

def test_close_short_loss(setup, core,
                          open, close,
                          short,
                          VEL, STX):
    setup()

    tx = open(VEL, STX, False, d(10), 2, price=d(5), sender=short)
    chain.mine(10_000)

    tx = close(VEL, STX, 1, price=d(6), sender=short)
    assert not tx.failed
    logs = core.Close.from_receipt(tx)
    print(logs[0].value[2])

    C = 10_000_000 - 10_000
    leverage = 2
    p0 = 5
    p1 = 6
    remaining = 9989901
    # payout = remaining * p1 + (p0 - p1)(collateral * leverage)
    profit = (p0 - p1) * (C * leverage)
    payout_as_base = remaining * p1 + profit

    loss = -profit
    assert loss == 19980000

    left = (remaining * p1 - loss) // p1
    assert left == 6659901

    fee = 10_000
    assert logs[0].value[1]             == [0, 0, 0, 0, 99, 99, 9989901]
    assert logs[0].value[2]             == [loss, 0, left, payout_as_base]         # [loss, profit, remaining, payout]
    assert VEL.balanceOf(short)         == 10_000_000_000 - 10_000_000
    assert STX.balanceOf(short)         == 10_000_000_000 + payout_as_base
    assert VEL.balanceOf(core.address)  == 10_000_000_000 + 10_000_000 - fee
    assert STX.balanceOf(core.address)  == 50_000_000_000 - payout_as_base


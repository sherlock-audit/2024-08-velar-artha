from ape import reverts
import pytest
from ape.logging import logger
from conftest import d

ERR_PERMISSIONS   = "PERMISSIONS"
ERR_INVARIANTS    = "INVARIANTS"
ERR_PRECONDITIONS = "PRECONDITIONS"

# fixtures

@pytest.fixture
def setup(core,
          oracle, api, pools, fees, positions,
          owner, lp_provider, lp_provider2, long, short, VEL, STX, LP, mint_token):
    def setup():

      # NOTE: adding all of these bacause otherwise it's flaky as fuck!
      pools.CORE()      == core
      fees.CORE()       == core
      positions.CORE()  == core
      oracle.API()      == api
      core.API()        == api

      core.fresh("VEL-STX", VEL, STX, LP, sender=owner)
      mint_token(VEL, d(100_000), lp_provider)
      mint_token(STX, d(100_000), lp_provider)
      mint_token(VEL, d(100_000), lp_provider2)
      mint_token(STX, d(100_000), lp_provider2)
      mint_token(VEL, d(10_000) , long)
      mint_token(STX, d(10_000) , long)
      mint_token(VEL, d(10_000) , short)
      mint_token(STX, d(10_000) , short)
      VEL.approve(core.address, d(100_000), sender=lp_provider)
      STX.approve(core.address, d(100_000), sender=lp_provider)
      VEL.approve(core.address, d(100_000), sender=lp_provider2)
      STX.approve(core.address, d(100_000), sender=lp_provider2)
      VEL.approve(core.address, d(10_000) , sender=long)
      STX.approve(core.address, d(10_000) , sender=long)
      VEL.approve(core.address, d(10_000) , sender=short)
      STX.approve(core.address, d(10_000) , sender=short)
    return setup

# test

def test_mint_twice(setup,
                    core,
                    mint,
                    lp_provider, lp_provider2,
                    VEL, STX, LP):
    setup()

    tx = mint(VEL, STX, LP, d(100), 0, price=d(5), sender=lp_provider)
    logs = core.Mint.from_receipt(tx)
    assert logs[0].lp_amt == d(500)

    tx = mint(VEL, STX, LP, d(1000), d(500), price=d(5), sender=lp_provider2)
    logs = core.Mint.from_receipt(tx)
    assert logs[0].lp_amt == d(5500)

    assert VEL.balanceOf(lp_provider)  ==  99_900_000_000
    assert VEL.balanceOf(lp_provider2) ==  99_000_000_000
    assert STX.balanceOf(lp_provider)  == 100_000_000_000
    assert STX.balanceOf(lp_provider2) ==  99_500_000_000
    assert LP.balanceOf(lp_provider)   ==     500_000_000
    assert LP.balanceOf(lp_provider2)  ==   5_500_000_000


def test_mint_twice_in_same_block(setup,
                                  mint,
                                  lp_provider, lp_provider2,
                                  VEL, STX, LP):
    setup()

    transactions = [
        mint(VEL, STX, LP, d(100) , 0     , price=d(5), sender=lp_provider , required_confs=0, silent=True),
        mint(VEL, STX, LP, d(1000), d(500), price=d(5), sender=lp_provider2, required_confs=0, silent=True),
    ]
    assert [tx.status == 1 for tx in transactions]


def test_open_twice(setup, core,
                    mint, open,
                    lp_provider, long, short,
                    VEL, STX, LP):
    setup()

    mint(VEL, STX, LP, d(10_000), d(50_000), price=d(5), sender=lp_provider)

    tx   = open(VEL, STX, True, d(100), 2, price=d(5), sender=long)
    logs = core.Open.from_receipt(tx)

    assert logs[0].position[5]    == 99_900_000
    assert logs[0].position[7]    == 39_960_000

    tx   = open(VEL, STX, False, d(100), 2, price=d(5), sender=short)
    logs = core.Open.from_receipt(tx)
    assert logs[0].position[5]    ==  99_900_000
    assert logs[0].position[7]    == 999_000_000

    assert VEL.balanceOf(long)   == 10_000_000_000, "long VEL"
    assert STX.balanceOf(long)   ==  9_900_000_000, "long STX"
    assert VEL.balanceOf(short)  ==  9_900_000_000, "short VEL"
    assert STX.balanceOf(short)  == 10_000_000_000, "short STX"


def test_open_twice_in_same_block(setup,
                                  mint, open,
                                  lp_provider, long, short,
                                  VEL, STX, LP):
    setup()

    mint(VEL, STX, LP, d(10_000), d(50_000), price=d(5), sender=lp_provider)

    transactions = [
      open(VEL, STX, True , d(100), 2, price=d(5), sender=long , required_confs=0, silent=True),
      open(VEL, STX, False, d(100), 2, price=d(5), sender=short, required_confs=0, silent=True),
    ]
    assert [tx.status == 1 for tx in transactions]


def test_mint_open_burn(setup, core,
                        mint, open, burn,
                        lp_provider, long,
                        VEL, STX, LP):
    setup()

    tx = mint(VEL, STX, LP, d(10_000), d(50_000), price=d(5), sender=lp_provider)
    logs = core.Mint.from_receipt(tx)
    amt = logs[0].lp_amt
    logger.info(amt)

    tx = open(VEL, STX, True , d(100), 2, price=d(5), sender=long)
    assert not tx.failed, "open"

    # NOTE: does not revert with hardhat
    with reverts():
        tx = burn(VEL, STX, LP, amt, price=d(5), sender=lp_provider)
        logger.info(tx.decode_logs(core.CalcBurn))

    tx = burn(VEL, STX, LP, amt//100, price=d(5), sender=lp_provider)
    assert not tx.failed, "2nd burn"
    logger.info(tx.decode_logs(core.Burn))

import pytest
from ape.logging import logger
from ape import chain
from conftest import d

ERR_PERMISSIONS   = "PERMISSIONS"
ERR_INVARIANTS    = "INVARIANTS"
ERR_PRECONDITIONS = "PRECONDITIONS"

# fixtures

@pytest.fixture
def setup(core,
          oracle, api, pools, fees, positions,
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
    return setup

# test

def test_mint_open_open_close_burn(setup, core,
                                   mint, burn, open, close,
                                   owner, lp_provider, long, short,
                                   VEL, STX, LP):
    setup()

    FEE_RECEIVER = owner
    FEE_RECIEVER_BALANCE_BEFORE = VEL.balanceOf(FEE_RECEIVER)

    # mint

    tx  = mint(VEL, STX, LP, d(10_000), d(50_000), price=d(5), sender=lp_provider)
    log = core.Mint.from_receipt(tx)[0]
    assert log.lp_amt       == d(100_000)
    assert log.base_amt     == d(10_000)
    assert log.quote_amt    == d(50_000)
    assert log.total_supply == 0

    assert VEL.balanceOf(lp_provider) == d(90_000)

    # open long position

    tx  = open(VEL, STX, True, d(2), 2, price=d(5), sender=long)
    log = core.Open.from_receipt(tx)[0]
    logger.info(tx.model_computed_fields)
    logger.info(tx.decode_logs(core.Open))
    assert not tx.failed, "open long"

    chain.mine(10_000)

    assert log.pool[5]  == d(10_000)
    assert log.pool[6]  == d(50_000)
    assert log.pool[7]  == 0
    assert log.pool[8]  == 0
    assert log.pool[9]  == 0
    assert log.pool[10] == 0
    assert log.pool     == [1, "VEL-STX", VEL, STX, LP, d(10_000), d(50_000), 0, 0, 0, 0]

    assert log.position[4]  == True
    assert log.position[5]  == 1998000
    assert log.position[6]  == 2
    assert log.position[7]  == 799200
    assert log.position[8]  == d(5)
    assert log.position[9]  == 0
    assert log.position[10] == 35
    assert log.position[11] == 0
    assert log.position[12] == (0, 1998000)
    assert log.position[13] == (799200, 0)

    # open short position

    tx = open(VEL, STX, False, d(1), 2, price=d(5), sender=short)
    assert not tx.failed, "open short"
    log = core.Open.from_receipt(tx)[0]

    assert log.pool[5]  == d(10_000)
    assert log.pool[6]  == d(50_000)
    assert log.pool[7]  == 799200
    assert log.pool[8]  == 0
    assert log.pool[9]  == 0
    assert log.pool[10] == 1998000

    assert log.position[4]  == False
    assert log.position[5]  == 999000
    assert log.position[6]  == 2
    assert log.position[7]  == 9990000
    assert log.position[8]  == d(5)
    assert log.position[9]  == 0
    assert log.position[10] == 10036
    assert log.position[11] == 0
    assert log.position[12] == (999000, 0)
    assert log.position[13] == (0, 9990000)

    chain.mine(10_000)

    # close long position

    tx  = close(VEL, STX, 1, price=d(5), sender=long)
    log = core.Close.from_receipt(tx)[0]
    assert not tx.failed, "close long"

    chain.mine(10_000)

    # burn

    tx  = burn(VEL, STX, LP, d(10_000), price=d(5), sender=lp_provider)
    log = core.Burn.from_receipt(tx)[0]

    assert log.base_amt   == 1000599404
    assert log.quote_amt  == 4997002982

    assert log.pool[5]    == 9999600408
    assert log.pool[6]    == 50001998000
    assert log.pool[7]    == 0
    assert log.pool[8]    == 9990000
    assert log.pool[9]    == 999000
    assert log.pool[10]   == 0

    assert LP.balanceOf(lp_provider)   == 90_000_000_000
    assert VEL.balanceOf(core)         == 9000000004
    assert STX.balanceOf(core)         == 45004995018
    assert VEL.balanceOf(lp_provider)  == 90_000_000_000 + 1000599404
    assert STX.balanceOf(lp_provider)  == 50_000_000_000 + 4997002982
    assert VEL.balanceOf(FEE_RECEIVER) == FEE_RECIEVER_BALANCE_BEFORE + 1000

from ape import reverts
import pytest
from conftest import d

ERR_PRECONDITIONS = "PRECONDITIONS"
ERR_PERMISSIONS   = "PERMISSIONS"

# helpers

def extend(X, xm, m): return X + xm * m
def slice(yi, yj): return yj - yi

# fixtures

@pytest.fixture
def setup_pool(core, mint, owner, lp_provider, long, short, VEL, STX, LP, mint_token):
    def setup():
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

def test_init(fees, math, params, pools, positions, core):
    assert fees.MATH()       == math
    assert fees.PARAMS()     == params
    assert fees.POOLS()      == pools
    assert fees.POSITIONS()  == positions
    assert fees.CORE()       == core

def test_lookup(fees):
    assert fees.lookup(1) == {
      'id'                   : 0,
      't0'                   : 0,
      't1'                   : 0,
      'borrowing_long'       : 0,
      'borrowing_short'      : 0,
      'funding_long'         : 0,
      'funding_short'        : 0,
      'long_collateral'      : 0,
      'short_collateral'     : 0,
      'borrowing_long_sum'   : 0,
      'borrowing_short_sum'  : 0,
      'funding_long_sum'     : 0,
      'funding_short_sum'    : 0,
      'received_long_sum'    : 0,
      'received_short_sum'   : 0,
  }

def test_fees_at_block(fees, owner):
    assert fees.fees_at_block(2, 1, sender=owner) == {
      'id'                   : 0,
      't0'                   : 0,
      't1'                   : 0,
      'borrowing_long'       : 0,
      'borrowing_short'      : 0,
      'funding_long'         : 0,
      'funding_short'        : 0,
      'long_collateral'      : 0,
      'short_collateral'     : 0,
      'borrowing_long_sum'   : 0,
      'borrowing_short_sum'  : 0,
      'funding_long_sum'     : 0,
      'funding_short_sum'    : 0,
      'received_long_sum'    : 0,
      'received_short_sum'   : 0,
    }

# NOTE: does not capture 2nd revert with hardhat
def test_update(fees, api, positions, pools, params, core, owner):
    with reverts(ERR_PERMISSIONS):
        fees.update(1, sender=owner)
    # core.balance += eth(1)                # fund contract
    # fees.update(1, sender=core)           # None :TypeError
    # with reverts():
    #     fees.update(1, sender=core)

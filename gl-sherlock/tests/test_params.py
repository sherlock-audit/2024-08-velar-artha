from ape import accounts
import pytest
from ape.logging import logger
from conftest import tokens

# Params.vy

# helpers

def ctx(p, bd, qd):
    return {'price': p, 'base_decimals': bd, 'quote_decimals': qd}

BASE_FEE = 1 # * 1_000_000

Status = {
  'OPEN'        : 1,
  'CLOSED'      : 2,
  'LIQUIDATABLE': 4,
}

# dummy values

POOL = {
  'id'               : 1,
  'symbol'           : 'VEL-STX',
  'base_token'       : 0, #VEL,
  'quote_token'      : 0, #STX,
  'lp_token'         : 0, #lpToken,
  'base_reserves'    : 0,
  'quote_reserves'   : 0,
  'base_interest'    : 0,
  'quote_interest'   : 0,
  'base_collateral'  : 0,
  'quote_collateral' : 0,
}

POS = {
  'id'                : 1,
  'pool'              : 1,
  'user'              : 0,
  'status'            : Status['OPEN'],
  'long'              : True,
  'collateral'        : 1,
  'leverage'          : 1,
  'interest'          : 1,
  'entry_price'       : 1,
  'exit_price'        : 0,
  'opened_at'         : 1,
  'closed_at'         : 0,
  'collateral_tagged' : tokens(0, 0),
  'interest_tagged'   : tokens(0, 0),
}

PNL = {
  'loss'     : 0,
  'profit'   : 0,
  'remaining': 0,
  'payout'   : 0,
}

# helpers

def pool(bc, qc):
    return {
      **POOL,
      'base_reserves'    : bc*100,
      'quote_reserves'   : qc*100,
      'base_interest'    : bc//100,
      'quote_interest'   : qc//100,
      'base_collateral'  : bc,
      'quote_collateral' : qc,
    }

# test

def test_static_fees(params):
    assert params.static_fees(10_000_000) == {
        'remaining' : 9_990_000,
        'fee'       : 10_000,
        'x'         : 10_000_000,
    }

def test_dynamic_fees_initial(params):
    p = {
        **POOL,
        'base_interest'   : 0,
        'base_reserves'   : 0,
        'quote_interest'  : 0,
        'quote_reserves'  : 0,
        'base_collateral' : 0,
        'quote_collateral': 0,
    }
    fees = params.dynamic_fees(p)
    logger.info(fees)
    assert fees == {
        'borrowing_long'  : BASE_FEE,
        'borrowing_short' : BASE_FEE,
        'funding_long'    : 0,
        'funding_short'   : 0,
    }

def test_dynamic_fees_unbiased(params):
    p = pool(1_000000_000_000, 5_000_000_000_000)

    fees =  params.dynamic_fees(p)
    assert fees == {
        'borrowing_long'  : BASE_FEE,
        'borrowing_short' : BASE_FEE,
        'funding_long'    : 0,
        'funding_short'   : 0,
    }

def test_dynamic_fees_biased(params):
    p = {
        **POOL,
        'base_interest'   : 100000000000,
        'base_reserves'   : 1000000000000,
        'quote_interest'  : 50000000,
        'quote_reserves'  : 1000000000000,
        'base_collateral' : 0,
        'quote_collateral': 0,
    }
    fees = params.dynamic_fees(p)
    print(fees)
    assert fees == {
        'borrowing_long'  : BASE_FEE,
        'borrowing_short' : BASE_FEE,
        'funding_long'    : BASE_FEE,
        'funding_short'   : 0,
    }

# uses position long, interest, leverage
def test_is_legal_position(params):
    assert params.is_legal_position(
        # pool(1_000_000_000_000, 5_000_000_000_000),
        POOL,
        { **POS,
         'collateral': 20_000_000,
         'leverage': 2,
         'long': True
        },
    ) == True, "ok leverage, enough pool reserves"

    assert params.is_legal_position(
        POOL,
        { **POS,
         'collateral': 20_000_000,
         'leverage': 11,
         'long': False,
        },
    ) == False, "over-leveraged"

    assert params.is_legal_position(
        POOL,
        { **POS,
         'collateral': 10_000_000_000_000,
         'leverage': 2,
         'long': True,
        },
    ) == False, "collateral > allowed"

# uses position.collateral, position.leverage & pnl.remaining
def test_is_liquidatable(params):
    assert params.is_liquidatable(
        { **POS, 'collateral': 10_000_000 },
        { **PNL, 'remaining' : 10_000_000 },
    ) == False, "all collateral remaining"
    assert params.is_liquidatable(
        { **POS, 'collateral': 10_000_000 },
        { **PNL, 'remaining' : 2_000_000 },
    )   == False
    assert params.is_liquidatable(
        { **POS, 'collateral': 10_000_000, 'leverage': 2 },
        { **PNL, 'remaining' : 200_000 },
    ) == True

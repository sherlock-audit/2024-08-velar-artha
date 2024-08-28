from conftest import eth

def test_fresh(chain, fees, core, owner, networks):
  core.balance += eth(1)                # fund contract
  res = fees.fresh(1, sender=core)
  blocknr = chain.blocks.head.number
  assert res.return_value == {
    'id'                   : 1,
    't0'                   : blocknr,
    't1'                   : blocknr,
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
  assert fees.lookup(1, sender=owner) == res.return_value

########################################################################
API        : public(address)
DEPLOYER   : address
INITIALIZED: bool
EXTRACTOR  : public(Extractor)
FEED_ID    : public(bytes32)
DECIMALS   : public(uint256)

@external
def __init__():
  self.DEPLOYER    = msg.sender
  self.INITIALIZED = False

@external
def __init__2(
  api      : address,
  extractor: address,
  feed_id  : bytes32,
  decimals : uint256,
):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  assert not self.INITIALIZED       , ERR_INVARIANTS
  self.INITIALIZED = True

  self.API       = api
  self.EXTRACTOR = Extractor(extractor)
  self.FEED_ID   = feed_id
  self.DECIMALS  = decimals
  self.TIMESTAMP = 0

@internal
def _INTERNAL():
  assert msg.sender == self.API, ERR_PERMISSIONS

@external
def set_extractor(new_extractor: address):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  self.EXTRACTOR = Extractor(new_extractor)

@external
def set_deployer(new_deployer: address):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  self.DEPLOYER = new_deployer

@external
def set_feed_id(new_feed_id: bytes32):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  self.FEED_ID = new_feed_id

@external
def set_decimals(new_decimals: uint256):
  assert msg.sender == self.DEPLOYER, ERR_PERMISSIONS
  self.DECIMALS = new_decimals

########################################################################
@external
def price(
    quote_decimals: uint256,
    desired       : uint256,
    slippage      : uint256,
    payload       : Bytes[224]
) -> uint256:
  """
  Certify a price.
  - parses oracle payload via an extractor contract
  - checks that oracle price matches user expectations
  - checks that oracle price is not older than previous oracle price
  - locks in block price to avoid frontrunning
  """
  self._INTERNAL()
  price      : uint256 = self.extract_price(quote_decimals, payload)
  block_price: uint256 = self.get_or_set_block_price(price)
  acceptable : bool    = self.check_slippage(block_price, desired, slippage)
  valid      : bool    = self.check_price(block_price)
  assert acceptable, ERR_PRECONDITIONS
  assert valid     , ERR_PRECONDITIONS
  return block_price

########################################################################
TIMESTAMP: public(uint256)

@internal
def extract_price(
    quote_decimals: uint256,
    payload       : Bytes[224]
) -> uint256:
  price: uint256 = 0
  ts   : uint256 = 0
  (price, ts) = self.EXTRACTOR.extractPrice(self.FEED_ID, payload)

  # Redstone allows prices ~10 seconds old, discourage replay attacks
  assert ts >= self.TIMESTAMP, "ERR_ORACLE"
  self.TIMESTAMP = ts

  # price is quote per unit base, convert to same precision as quote
  pd   : uint256 = self.DECIMALS
  qd   : uint256 = quote_decimals
  s    : bool    = pd >= qd
  n    : uint256 = pd - qd if s else qd - pd
  m    : uint256 = 10 ** n
  p    : uint256 = price / m if s else price * m
  return p

########################################################################
PRICES: HashMap[uint256, uint256]

@internal
def get_or_set_block_price(current: uint256) -> uint256:
  """
  The first transaction in each block will set the price for that block.
  """
  block_price: uint256 = self.PRICES[block.number]
  if block_price == 0:
    self.PRICES[block.number] = current
    return current
  else:
    return block_price

########################################################################
@internal
@pure
def check_slippage(current: uint256, desired: uint256, slippage: uint256) -> bool:
  if current > desired: return (current - desired) <= slippage
  else                : return (desired - current) <= slippage

@internal
@pure
def check_price(price: uint256) -> bool:
  return price > 0

# eof

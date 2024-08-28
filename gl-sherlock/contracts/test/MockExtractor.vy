
interface Extractor:
  def extractPrice(feed_id: bytes32, payload: Bytes[224]) -> (uint256, uint256): view

implements: Extractor

@external
@view
def extractPrice(feed_id: bytes32, payload: Bytes[224]) -> (uint256, uint256):
  price: bytes32 = convert(slice(payload, 192, 32), bytes32)
  return (convert(price, uint256), block.timestamp)

interface ERC20Plus:
  def mint(to: address, amt: uint256)    -> bool : nonpayable
  def burn(_from: address, amt: uint256) -> bool : nonpayable

# eof

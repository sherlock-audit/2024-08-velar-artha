# LP tokens (ERC20 plus mint/burn).

#=======================================================================
from vyper.interfaces import ERC20
from IERC20Plus       import ERC20Plus

implements: ERC20
implements: ERC20Plus

#=======================================================================
name       : public(String[64])
symbol     : public(String[32])
decimals   : public(uint256)
totalSupply: public(uint256)

OWNER      : public(address) # set to core

@external
def __init__(
  name       : String[64],
  symbol     : String[32],
  decimals   : uint256):
  self.name        = name
  self.symbol      = symbol
  self.decimals    = decimals
  self.totalSupply = 0
  self.OWNER       = msg.sender

@external
def set_owner(new_owner: address) -> bool:
    assert msg.sender == self.OWNER, "ERR_PERMISSIONS"
    self.OWNER = new_owner
    return True

#=======================================================================
balanceOf: public(HashMap[address, uint256])

event Transfer:
  _from : indexed(address)
  _to   : indexed(address)
  _value: uint256

@external
def transfer(to: address, amt: uint256) -> bool:
  _from: address         = msg.sender
  self.balanceOf[_from] -= amt
  self.balanceOf[to]    += amt
  log Transfer(_from, to, amt)
  return True

@external
def transferFrom(_from: address, to: address, amt: uint256) -> bool:
  self.use(_from, amt)
  self.balanceOf[_from] -= amt
  self.balanceOf[to]    += amt
  log Transfer(_from, to, amt)
  return True

#=======================================================================
allowance: public(HashMap[address, HashMap[address, uint256]])

event Approval:
  _owner   : indexed(address)
  _spender : indexed(address)
  _value   : uint256

event Usage:
  _user    : indexed(address)
  _delegate: indexed(address)
  _value   : uint256

@external
def approve(delegate: address, amt: uint256) -> bool:
  user: address                  = msg.sender
  self.allowance[user][delegate] = amt
  log Approval(user, delegate, amt)
  return True

# permission check via underflow
@internal
def use(user: address, amt: uint256) -> bool:
  delegate: address               = msg.sender
  self.allowance[user][delegate] -= amt
  log Usage(user, delegate, amt)
  return True

#=======================================================================
event Mint:
  _to   : indexed(address)
  _value: uint256

event Burn:
  _from : indexed(address)
  _value: uint256

@external
def mint(to: address, amt: uint256) -> bool:
  assert msg.sender == self.OWNER, "ERR_PERMISSIONS"
  self.totalSupply   += amt
  self.balanceOf[to] += amt
  log Transfer(empty(address), to, amt)
  return True

@external
def burn(_from: address, amt: uint256) -> bool:
  assert msg.sender == self.OWNER, "ERR_PERMISSIONS"
  self.totalSupply      -= amt
  self.balanceOf[_from] -= amt
  log Transfer(_from, empty(address), amt)
  return True

# eof

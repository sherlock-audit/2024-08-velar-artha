from vyper.interfaces import ERC20

implements: ERC20

owner       : address
totalSupply : public(uint256)
name        : public(String[32])
symbol      : public(String[32])
decimals    : public(uint256)

balances    : HashMap[address, uint256]
allowances  : HashMap[address, HashMap[address, uint256]]

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    amount: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

@external
def __init__(
    _name        : String[32],
    _symbol      : String[32],
    _decimals    : uint256,
    _totalSupply : uint256):
    self.name     = _name
    self.symbol   = _symbol
    self.decimals = _decimals
    self.owner    = msg.sender
    self.totalSupply = _totalSupply * (10 ** _decimals)
    self.balances[self.owner] = self.totalSupply

@internal
def _transferCoins(_src: address, _dst: address, _amount: uint256):
    assert _src != empty(address), "transfer from the zero address"
    assert _dst != empty(address), "transfer to the zero address"
    self.balances[_src] -= _amount
    self.balances[_dst] += _amount

@external
def transfer(_to: address, _value: uint256) -> bool:
    assert self.balances[msg.sender] >= _value, "not enough balance"
    self._transferCoins(msg.sender, _to, _value)
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    allowance: uint256 = self.allowances[_from][msg.sender]
    assert self.balances[_from] >= _value and allowance >= _value
    self._transferCoins(_from, _to, _value)
    self.allowances[_from][msg.sender] -= _value
    log Transfer(_from, _to, _value)
    return True

@view
@external
def balanceOf(_owner: address) -> uint256:
  	return self.balances[_owner]

@view
@external
def allowance(_owner: address, _spender: address) -> uint256:
	  return self.allowances[_owner][_spender]

@external
def approve(_spender: address, _value: uint256) -> bool:
    self.allowances[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

# @external
# def increaseAllowance(spender: address, _value: uint256) -> bool:
#     assert spender != empty(address)
#     self.allowances[msg.sender][spender] += _value
#     log Approval(msg.sender, spender, self.allowances[msg.sender][spender])
#     return True

# @external
# def decreaseAllowance(spender: address, _value: uint256) -> bool:
#     assert spender != empty(address)
#     self.allowances[msg.sender][spender] -= _value
#     log Approval(msg.sender, spender, self.allowances[msg.sender][spender])
#     return True

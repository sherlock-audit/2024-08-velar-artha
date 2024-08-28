import ape
import pytest

# ERC20token.vy

@pytest.fixture
def token(project, owner):
    return owner.deploy(project.ERC20Plus, "token-token", "token", 0)

def test_init(token, owner):
    assert token.OWNER()       == owner
    assert token.name()        == "token-token"
    assert token.symbol()      == "token"
    assert token.decimals()    == 0
    assert token.totalSupply() == 0

def test_set_owner(token, core, owner, long):
    with ape.reverts("ERR_PERMISSIONS"):
      token.set_owner(core, sender=long)

    tx = token.set_owner(core, sender=owner)
    assert not tx.failed
    assert token.OWNER()       == core
    assert token.balanceOf(owner) == 0

def test__mint_burn(token, core, owner, long):
    with ape.reverts("ERR_PERMISSIONS"):
        token.mint(core, 10_000, sender=long)

    assert token.balanceOf(owner) == 0
    assert token.totalSupply() == 0
    tx = token.mint(long, 10_000, sender=owner)
    assert not tx.failed
    assert token.balanceOf(long) == 10_000
    assert token.totalSupply() == 10_000
    tx = token.burn(long, 10_000, sender=owner)
    assert not tx.failed
    assert token.balanceOf(long) == 0
    assert token.totalSupply() == 0

def test_approvals_1(token, owner, long, short):
    A = long
    B = short
    token.mint(A, 1000, sender=owner)
    assert token.balanceOf(A) == 1000
    assert token.totalSupply() == 1000

    # allowance > balance
    token.approve(B, 500, sender=A)
    assert token.allowance(A, B, sender=A) == 500, "Allowance before"
    tx = token.transfer(owner, 800, sender=A)
    assert not tx.failed
    with ape.reverts():           # "Integer underflow"
        token.transferFrom(A, B, 500, sender=B)
    assert token.balanceOf(A) == 200
    assert token.balanceOf(B) == 0
    assert token.allowance(A, B, sender=A) == 500, "Allowance after"

def test_approvals_2(token, owner, long, short):
    A = long
    B = short
    token.mint(A, 1000, sender=owner)
    assert token.balanceOf(A) == 1000

    # transfer > allowance
    token.approve(B, 500, sender=A)
    with ape.reverts():           # "Integer underflow"
        token.transferFrom(A, B, 1000, sender=B)
    assert token.balanceOf(A) == 1000
    assert token.balanceOf(B) == 0
    assert token.allowance(A, B, sender=A) == 500, "Allowance after"

def test_approvals_3(token, owner, long):
    A = long
    token.mint(A, 1000, sender=owner)
    assert token.balanceOf(A) == 1000

    # approve oneself
    token.approve(A, 500, sender=A)
    token.transferFrom(A, A, 500, sender=A)
    assert token.balanceOf(A) == 1000
    assert token.allowance(A, A, sender=A) == 0

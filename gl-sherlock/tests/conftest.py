import pytest
from ape import accounts
from web3 import Web3, EthereumTesterProvider

w3 = Web3(EthereumTesterProvider())

SCOPE = "function"

# accounts

@pytest.fixture(scope=SCOPE)
def owner(): return accounts.test_accounts[0]

@pytest.fixture(scope=SCOPE)
def lp_provider(accounts): return accounts[1]

@pytest.fixture(scope=SCOPE)
def long(accounts): return accounts[2]

@pytest.fixture(scope=SCOPE)
def short(accounts): return accounts[3]

@pytest.fixture(scope=SCOPE)
def lp_provider2(accounts): return accounts[4]

# tokens

SUPPLY   = 1_000_000_000
DECIMALS = 6

@pytest.fixture(scope=SCOPE)
def create_token(project, owner):
    def create_token(name):
        return owner.deploy(project.ERC20, name, name, DECIMALS, SUPPLY)
    return create_token

@pytest.fixture(scope=SCOPE)
def VEL(create_token): return create_token("velar")

@pytest.fixture(scope=SCOPE)
def STX(create_token): return create_token("wstx")

@pytest.fixture(scope=SCOPE)
def USD(create_token): return create_token("usd")

@pytest.fixture(scope=SCOPE)
def LP(project, core, owner):
    c = owner.deploy(project.ERC20Plus, "lp-token", "lp", 0)
    c.set_owner(core, sender=owner)
    return c

@pytest.fixture(scope=SCOPE)
def LP2(project, core, owner):
    c = owner.deploy(project.ERC20Plus, "lp-token-2", "lp2", 0)
    c.set_owner(core, sender=owner)
    return c

# ----------- Params -----------------

PARAMS = {
  'MIN_FEE'               : 1,
  'MAX_FEE'               : 1,

  # Fraction of collateral (e.g. 1000).
  'PROTOCOL_FEE'          : 1000,

  # Fraction of remaining collateral (e.g. 2)
  'LIQUIDATION_FEE'       : 2,

  # Depend on coin decimals.
  'MIN_LONG_COLLATERAL'   : 1,
  'MAX_LONG_COLLATERAL'   : 1_000_000_000,
  'MIN_SHORT_COLLATERAL'  : 1,
  'MAX_SHORT_COLLATERAL'  : 1_000_000_000,

  # E.g. 1 and 10.
  'MIN_LONG_LEVERAGE'     : 1,
  'MAX_LONG_LEVERAGE'     : 10,
  'MIN_SHORT_LEVERAGE'    : 1,
  'MAX_SHORT_LEVERAGE'    : 10,

  # C.f. is_liquidatable, e.g. 10.
  'LIQUIDATION_THRESHOLD' : 1,
}

FEED_ID = b"BTC"

# ------------------------------------

# contracts

@pytest.fixture(scope=SCOPE)
def math(owner, project):
    return owner.deploy(project.math)

@pytest.fixture(scope=SCOPE)
def params_(owner, project): return owner.deploy(project.params)

@pytest.fixture(scope=SCOPE)
def oracle_(owner, project): return owner.deploy(project.oracle)

@pytest.fixture(scope=SCOPE)
def fees_(owner, project): return owner.deploy(project.fees)

@pytest.fixture(scope=SCOPE)
def pools_(owner, project): return owner.deploy(project.pools)

@pytest.fixture(scope=SCOPE)
def positions_(owner, project): return owner.deploy(project.positions)

@pytest.fixture(scope=SCOPE)
def core_(owner, project): return owner.deploy(project.core)

@pytest.fixture(scope=SCOPE)
def api_(owner, project): return owner.deploy(project.api)

# test-contracts

@pytest.fixture(scope=SCOPE)
def extractor(owner, project): return owner.deploy(project.MockExtractor)

# init

@pytest.fixture(scope=SCOPE)
def params(owner, params_):
    params_.__init__2(PARAMS, sender=owner)
    return params_

@pytest.fixture(scope=SCOPE)
def oracle(owner, oracle_, api_, extractor):
    oracle_.__init__2(api_, extractor, FEED_ID, 6, sender=owner)
    return oracle_

@pytest.fixture(scope=SCOPE)
def fees(owner, fees_, math, params, pools_, core_, positions_):
    fees_.__init__2(math, params, pools_, core_, positions_, sender=owner)
    return fees_

@pytest.fixture(scope=SCOPE)
def pools(owner, pools_, math, core_):
    pools_.__init__2(math, core_, sender=owner)
    return pools_

@pytest.fixture(scope=SCOPE)
def positions(owner, positions_, math, params, pools_, fees_, core_):
    positions_.__init__2(math, params, pools_, fees_, core_, sender=owner)
    return positions_

# NOTE: dummy collector address
@pytest.fixture(scope=SCOPE)
def core(owner, core_, math, params, pools_, fees_, positions_, api_):
    core_.__init__2(math, params, pools_, fees_, positions_, owner, api_, sender=owner)
    return core_

@pytest.fixture(scope=SCOPE)
def api(owner, api_, core_, oracle_):
    api_.__init__2(oracle_, core_, sender=owner)
    return api_

# ---------------- API ------------------------

def payload(price): return (price).to_bytes(224, "big")

def with_context(fun):
    def x(*args, **kwargs):
      price   = kwargs.get("price")
      del kwargs["price"]
      return fun(*args, price, 1, payload(price), **kwargs)
    return x

@pytest.fixture
def mint(api): return with_context(api.mint)

@pytest.fixture
def burn(api): return with_context(api.burn)

@pytest.fixture
def open(api): return with_context(api.open)

@pytest.fixture
def close(api): return with_context(api.close)

@pytest.fixture
def liquidate(api): return with_context(api.liquidate)

# ----------------------------------------------

# helpers

@pytest.fixture(scope=SCOPE)
def mint_token(owner):
    def mint_token(token, amt, account):
        return token.transfer(account, amt, sender=owner)
    return mint_token

def ctx(price):
    return {
        'price': price,
        'base_decimals': 6,
        'quote_decimals': 6,
    }

def tokens(b, q):
    return {'base': b, 'quote': q}

def d(x): return x * 10**6

def eth(x): return x*10**18

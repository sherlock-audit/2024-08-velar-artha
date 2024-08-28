# Notes

* somewhat non-idiosynchratic codebase because we have to maintain versions of this
  in multiple languages and want to keep things between those as similar as possible
* each pool gets a full set of contracts (i.e. pool id is always 1)
* if you want to read the code in dependency order, c.f. the make all target or
  the call graph in api
* theres an overview comment in core
* the two main settables are the oracle extractor contract and the (fee) parameters
  we would like to eventually use an onchain oracle but for now that doesnt exist
  we would also like to put strict hardcoded bounds on the fees, but correct
  settings are impossible to determine without observing user behaviour so please
  assume they are set to something reasonable (~ slightly lower than industry
  standard)
* for precision issues, we do not care about small differences as long as they
  are safe. e.g. we do not care if a fee payment is a few decimals (tokens are
  assumed to have between 6 and 18 decimals) less than the correct value
  we would care if it was a little bit more than the correct value since
  that might be used to drain the pool of course!

# Usage

    $ npm install # downloads redstone sdk and hardhat
    $ make        # generates src/
    $ make test   # generates additional test contracts
    $ ape test    # runs testsuite
    $ ape test --network ::hardhat tests/hardhat.py # runs additional tests

You may have to edit the first line in GNUmakefile depending on how you like to
manage your python installation (defaults to ~/.local/bin i.e. local pip install).

# Requirements

    $ python --version
    Python 3.11.9
    $ pytest --version
    pytest 8.3.2
    $ pip list | grep hypothesis
    hypothesis 6.111.1
    $ vyper --version
    0.3.10
    $ ape --version
    0.8.12 (NOT 0.8.13)
    $ ape plugins list #should all be there when installing with recommended
    Installed Plugins
    etherscan    0.8.2
    foundry      0.8.4
    hardhat      0.8.1
    solidity     0.8.3
    vyper        0.8.4

<3

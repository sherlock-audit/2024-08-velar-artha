VYPER=$(HOME)/.local/bin/vyper
GIT=$(shell git rev-parse HEAD)
REDSTONE=node_modules/@redstone-finance/evm-connector/contracts

all: dirs vendor sol math params pools fees positions erc20plus core oracle api

release:
	mkdir release
	cp -r contracts                release
	cp -r src                      release
	cp -r target                   release
	cp -r abi                      release
	cp scripts/bob/address_book.py release
	tar czf release-$(GIT).tgz     release
	rm -rf release

clean:
	rm -rf src/*
	rm -rf target/*
	rm -rf abi/*

vendor:
	mkdir -p src/vendor/core
	mkdir -p src/vendor/data-services
	mkdir -p src/vendor/libs
	cp $(REDSTONE)/core/CalldataExtractor.sol           src/vendor/core
	cp $(REDSTONE)/core/RedstoneConstants.sol           src/vendor/core
	cp $(REDSTONE)/core/RedstoneConsumerBase.sol        src/vendor/core
	cp $(REDSTONE)/core/RedstoneConsumerNumericBase.sol src/vendor/core
	cp $(REDSTONE)/core/RedstoneDefaultsLib.sol         src/vendor/core
	cp $(REDSTONE)/libs/BitmapLib.sol                   src/vendor/libs
	cp $(REDSTONE)/libs/NumericArrayLib.sol             src/vendor/libs
	cp $(REDSTONE)/libs/SignatureLib.sol                src/vendor/libs
	cp $(REDSTONE)/data-services/PrimaryProdDataServiceConsumerBase.sol src/vendor/data-services

dirs:
	mkdir -p src
	mkdir	-p target
	mkdir -p abi

sol:
	cp contracts/RedstoneExtractor.sol src/RedstoneExtractor.sol

api:
	cat contracts/types.vy contracts/api.vy > src/api.vy
	$(VYPER)        src/api.vy > target/api.evm
	$(VYPER) -f abi src/api.vy > abi/api.json

core:
	cat contracts/types.vy contracts/core.vy > src/core.vy
	$(VYPER)        src/core.vy > target/core.evm
	$(VYPER) -f abi src/core.vy > abi/core.json

fees:
	cat contracts/types.vy contracts/fees.vy > src/fees.vy
	$(VYPER)        src/fees.vy > target/fees.evm
	$(VYPER) -f abi src/fees.vy > abi/fees.json

math:
	cat contracts/types.vy contracts/math.vy > src/math.vy
	$(VYPER)        src/math.vy > target/math.evm
	$(VYPER) -f abi src/math.vy > abi/math.json

oracle:
	cat contracts/types.vy contracts/oracle.vy > src/oracle.vy
	$(VYPER)        src/oracle.vy > target/oracle.evm
	$(VYPER) -f abi src/oracle.vy > abi/oracle.json

params:
	cat contracts/types.vy contracts/params.vy > src/params.vy
	$(VYPER)        src/params.vy > target/params.evm
	$(VYPER) -f abi src/params.vy > abi/params.json

pools:
	cat contracts/types.vy contracts/pools.vy > src/pools.vy
	$(VYPER)        src/pools.vy > target/pools.evm
	$(VYPER) -f abi src/pools.vy > abi/pools.json

positions:
	cat contracts/types.vy contracts/positions.vy > src/positions.vy
	$(VYPER)        src/positions.vy > target/positions.evm
	$(VYPER) -f abi src/positions.vy > abi/positions.json

# tokens
erc20plus:
	cp contracts/tokens/IERC20Plus.vy src/IERC20Plus.vy
	cp contracts/tokens/ERC20Plus.vy  src/ERC20Plus.vy
	$(VYPER)        src/ERC20Plus.vy > target/ERC20Plus.evm
	$(VYPER) -f abi src/ERC20Plus.vy > abi/ERC20Plus.json

test: all
	mkdir -p src/test
	cp contracts/test/ERC20.vy src/test/ERC20.vy
	cp contracts/test/MockExtractor.vy src/test/MockExtractor.vy

# eof

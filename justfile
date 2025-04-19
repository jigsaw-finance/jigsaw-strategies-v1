#!/usr/bin/env just --justfile

# load .env file
set dotenv-load

# pass recipe args as positional arguments to commands
set positional-arguments

set export

_default:
  just --list

# utility functions
start_time := `date +%s`
_timer:
    @echo "Task executed in $(($(date +%s) - {{ start_time }})) seconds"

clean-all: && _timer
	forge clean
	rm -rf coverage_report
	rm -rf lcov.info
	rm -rf typechain-types
	rm -rf artifacts
	rm -rf out

remove-modules: && _timer
	rm -rf .gitmodules
	rm -rf .git/modules/*
	rm -rf lib/forge-std
	touch .gitmodules
	git add .
	git commit -m "modules"

# Install the Modules
install: && _timer
	forge install foundry-rs/forge-std

# Update Dependencies
update: && _timer
	forge update

remap: && _timer
	forge remappings > remappings.txt

# Builds
build: && _timer
	forge clean
	forge build --names --sizes

format: && _timer
	forge fmt

test-all: && _timer
	forge test -vvvv --match-contract AaveV3StrategyTest
	forge test -vvvv --match-contract DineroStrategyTest
	forge test -vvvv --match-contract IonStrategyTest
	forge test -vvvv --match-contract PendleStrategyTest
	forge test -vvvv --match-contract ReservoirSavingStrategyTest
	forge test -vvvv --match-contract ReservoirMath
	forge test -vvvv --match-contract DeployAllTest


test-gas: && _timer
    forge test --gas-report

coverage-all: && _timer
	forge coverage --report lcov --allow-failure
	genhtml -o coverage --branch-coverage lcov.info --ignore-errors category

docs: && _timer
	forge doc --build

mt test: && _timer
	forge test -vvvvvv --match-test {{test}}

mp verbosity path: && _timer
	forge test -{{verbosity}} --match-path test/{{path}}

# Deploy StakerFactory
# This script deploys the StakerFactory contract and handles logging.
deploy-stakerFactory: && _timer
	#!/usr/bin/env bash
	echo "Deploying Staker Factory on chain $CHAIN ..."

	# Run the Forge script to deploy the StakerFactory
	forge script DeployStakerFactory --rpc-url $CHAIN --slow -vvvv --broadcast --verify --etherscan-api-key $(eval echo \${${CHAIN}_ETHERSCAN_API_KEY})
	
	# Update deployments.json
	FACTORY_ADDRESS=$(jq -r '.returns.stakerFactory.value' "broadcast/0_DeployStakerFactory.s.sol/$CHAIN_ID/run-latest.json")
	jq --arg chainId "$CHAIN_ID" --arg address "$FACTORY_ADDRESS" \
		'. + {STAKER_FACTORY: $address}' ./deployments.json > temp.json && mv temp.json ./deployments.json

# Deploy implementation
# This script deploys only the strategy implementation contract.
deploy-impl STRATEGY: && _timer
	#!/usr/bin/env bash
	echo "Deploying implementation for " {{STRATEGY}} " on chain $CHAIN ..."

	# Run the Forge script to deploy the implementation
	forge script DeployImpl -s "run(string memory _strategy)" {{STRATEGY}} --rpc-url $CHAIN --slow -vvvv --broadcast --verify --etherscan-api-key $(eval echo \${${CHAIN}_ETHERSCAN_API_KEY})

	# Update deployments.json
	IMPL_ADDRESS=$(jq -r '.returns.implementation.value' "broadcast/1_DeployImpl.s.sol/"$CHAIN_ID"/run-latest.json")
	jq --arg address "$IMPL_ADDRESS" --arg strategy "$STRATEGY" \
		'. + {($strategy + "_IMPL"):  $address}' ./deployments.json > temp.json && mv temp.json ./deployments.json

	echo "Implementation deployed at $IMPL_ADDRESS"
	
# Deploy proxy
# This script deploys the proxy and links it to the deployed implementation.
deploy-proxy STRATEGY: && _timer
	#!/usr/bin/env bash
	echo "Deploying proxy for " {{STRATEGY}} " on chain $CHAIN ..."

	# Run the Forge script to deploy the proxy
	forge script DeployProxy -s "run(string calldata _strategy)" {{STRATEGY}} --rpc-url $CHAIN --slow -vvvv --broadcast --verify --etherscan-api-key $(eval echo \${${CHAIN}_ETHERSCAN_API_KEY})
	
	# Save proxy addresses
	PROXIES=$(jq -c '.returns.proxies.value' "broadcast/2_DeployProxy.s.sol/${CHAIN_ID}/run-latest.json")

	# Update the deployments.json with properly formatted proxies
	jq --argjson proxies "$PROXIES" --arg strategy "$STRATEGY" \
	'. + {($strategy + "_PROXIES"): $proxies}' ./deployments.json > temp.json && mv temp.json ./deployments.json

	# echo "Proxies successfully deployed"

# Deploy both implementation and proxy
deploy-strategy STRATEGY: && _timer
	#!/usr/bin/env bash
	echo "Deploying full strategy " {{STRATEGY}} " on chain " ${CHAIN} "..."

	# Step 1: Deploy implementation
	just deploy-impl {{STRATEGY}}

	# Step 2: Deploy proxy
	just deploy-proxy {{STRATEGY}}
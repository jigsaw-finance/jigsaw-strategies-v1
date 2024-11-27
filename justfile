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
	forge test

test-gas: && _timer
    forge test --gas-report

coverage-all: && _timer
	forge coverage --report lcov
	genhtml -o coverage --branch-coverage lcov.info --ignore-errors category

docs: && _timer
	forge doc --build

mt test: && _timer
	forge test -vvvvvv --match-test {{test}}

mp verbosity path: && _timer
	forge test -{{verbosity}} --match-path test/{{path}}


# Deploy StakerFactory
# This script deploys the StakerFactory contract and handles logging.
deploy-stakerFactory CHAIN_ID BROADCAST:
	#!/usr/bin/env bash
	echo "Deploying Staker Factory on chain " {{CHAIN_ID}} "..."

	# Run the Forge script to deploy the StakerFactory
	forge script DeployStakerFactory --rpc-url {{CHAIN_ID}} --slow -vvvv {{BROADCAST}}

	# Save the deployed address
	FACTORY_ADDRESS=$(jq '.returns."1".value' "broadcast/DeployStakerFactory.s.sol/"{{CHAIN_ID}}"/run-latest.json" | xargs)

	# Update deployments.json
	jq --arg address "$FACTORY_ADDRESS" \
		'. + {"StakerFactory": {"CHAIN_ID": {{CHAIN_ID}}, "ADDRESS": $address}}' ./deployments.json > temp.json && mv temp.json ./deployments.json

	echo "Staker Factory deployed at $FACTORY_ADDRESS"

# Deploy implementation
# This script deploys only the strategy implementation contract.
deploy-impl STRATEGY CHAIN_ID BROADCAST:
	#!/usr/bin/env bash
	echo "Deploying implementation for " {{STRATEGY}} " on chain " {{CHAIN_ID}} "..."

	# Run the Forge script to deploy the implementation
	forge script DeployImpl -s "run(string memory _strategy)" {{STRATEGY}} --rpc-url {{CHAIN_ID}} --slow -vvvv {{BROADCAST}}

	# Save implementation address
	IMPL_ADDRESS=$(jq '.returns."0".value' "broadcast/1_DeployImpl.s.sol/"{{CHAIN_ID}}"/run-latest.json" | xargs)
	jq --arg address "$IMPL_ADDRESS" --arg strategy "$STRATEGY" \
		'. + {($strategy): {"IMPL": $address}}' ./deployments.json > temp.json && mv temp.json ./deployments.json

	echo "Implementation deployed at $IMPL_ADDRESS"

# Deploy proxy
# This script deploys the proxy and links it to the deployed implementation.
deploy-proxy STRATEGY IMPL_ADDRESS SALT CHAIN_ID BROADCAST:
	#!/usr/bin/env bash
	echo "Deploying proxy for " {{STRATEGY}} " on chain " {{CHAIN_ID}} " with implementation at " {{IMPL_ADDRESS}} "..."

	# Run the Forge script to deploy the proxy
	forge script DeployProxy -s "run(string calldata _strategy, address _implementation, bytes32 _salt)" {{STRATEGY}} {{IMPL_ADDRESS}} {{SALT}} --rpc-url {{CHAIN_ID}} --slow -vvvv {{BROADCAST}}

	# Save proxy address
	PROXY_ADDRESS=$(jq '.returns."0".value' "broadcast/2_DeployProxy.s.sol/"{{CHAIN_ID}}"/run-latest.json" | xargs)
	jq --arg address "$PROXY_ADDRESS" --arg strategy "$STRATEGY" \
		'. + {($strategy): (.[$strategy] // {} + {"PROXY": $address})}' ./deployments.json > temp.json && mv temp.json ./deployments.json

	echo "Proxy deployed at $PROXY_ADDRESS"

# Deploy both implementation and proxy
# This combines the above two steps for convenience.
deploy-strategy STRATEGY SALT CHAIN_ID BROADCAST:
	#!/usr/bin/env bash
	echo "Deploying full strategy " {{STRATEGY}} " on chain " {{CHAIN_ID}} "..."

	# Step 1: Deploy implementation
	just deploy-impl {{STRATEGY}} {{CHAIN_ID}} {{BROADCAST}}

	# Fetch implementation address
	IMPL_ADDRESS=$(jq -r --arg strategy "{{STRATEGY}}" '.[$strategy].IMPL' ./deployments.json)

	# Step 2: Deploy proxy
	just deploy-proxy {{STRATEGY}} $IMPL_ADDRESS {{SALT}} {{CHAIN_ID}} {{BROADCAST}}

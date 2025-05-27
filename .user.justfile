#!/usr/bin/env just --justfile

set dotenv-filename := ".env.tenderly"

# load .env file
set dotenv-load

# pass recipe args as positional arguments to commands
set positional-arguments

set export

# utility functions
start_time := `date +%s`
_timer:
    @echo "Task executed in $(($(date +%s) - {{ start_time }})) seconds"

# Deploy StakerFactory
# This script deploys the StakerFactory contract and handles logging.
tenderly-deploy-stakerFactory: && _timer
	#!/usr/bin/env bash
	echo "Deploying Staker Factory on chain $CHAIN ..."

	# Run the Forge script to deploy the StakerFactory
	forge script DeployStakerFactory --rpc-url $CHAIN --slow -vvvvv --broadcast --verify --etherscan-api-key ${TENDERLY_ETHERSCAN_API_KEY} --verifier-url ${TENDERLY_VERIFIER_URL}
	# Update deployments.json
	FACTORY_ADDRESS=$(jq -r '.returns.stakerFactory.value' "broadcast/0_DeployStakerFactory.s.sol/$CHAIN_ID/run-latest.json")
	jq --arg chainId "$CHAIN_ID" --arg address "$FACTORY_ADDRESS" \
		'. + {STAKER_FACTORY: $address}' ./deployments.json > temp.json && mv temp.json ./deployments.json

# Deploy implementation
# This script deploys only the strategy implementation contract.
tenderly-deploy-impl STRATEGY: && _timer
	#!/usr/bin/env bash
	echo "Deploying implementation for " {{STRATEGY}} " on chain $CHAIN ..."

	# Run the Forge script to deploy the implementation
	forge script DeployImpl -s "run(string memory _strategy)" {{STRATEGY}} --rpc-url $CHAIN --slow -vvvv --broadcast --verify --etherscan-api-key ${TENDERLY_ETHERSCAN_API_KEY} --verifier-url ${TENDERLY_VERIFIER_URL}

	# Update deployments.json
	IMPL_ADDRESS=$(jq -r '.returns.implementation.value' "broadcast/1_DeployImpl.s.sol/"$CHAIN_ID"/run-latest.json")
	jq --arg address "$IMPL_ADDRESS" --arg strategy "$STRATEGY" \
		'. + {($strategy + "_IMPL"):  $address}' ./deployments.json > temp.json && mv temp.json ./deployments.json

	echo "Implementation deployed at $IMPL_ADDRESS"
	
# Deploy proxy
# This script deploys the proxy and links it to the deployed implementation.
tenderly-deploy-proxy STRATEGY: && _timer
	#!/usr/bin/env bash
	echo "Deploying proxy for " {{STRATEGY}} " on chain $CHAIN ..."

	# Run the Forge script to deploy the proxy
	forge script DeployProxy -s "run(string calldata _strategy)" {{STRATEGY}} --rpc-url $CHAIN --slow -vvvvv --broadcast --verify --etherscan-api-key ${TENDERLY_ETHERSCAN_API_KEY} --verifier-url ${TENDERLY_VERIFIER_URL}
	
	# Save proxy addresses
	PROXIES=$(jq -c '.returns.proxies.value' "broadcast/2_DeployProxy.s.sol/${CHAIN_ID}/run-latest.json")

	# Update the deployments.json with properly formatted proxies
	jq --argjson proxies "$PROXIES" --arg strategy "$STRATEGY" \
	'. + {($strategy + "_PROXIES"): $proxies}' ./deployments.json > temp.json && mv temp.json ./deployments.json

	# echo "Proxies successfully deployed"

# Deploy both implementation and proxy
tenderly-deploy-strategy STRATEGY: && _timer
	#!/usr/bin/env bash
	echo "Deploying full strategy " {{STRATEGY}} " on chain " ${CHAIN} "..."

	# Step 1: Deploy implementation
	just -f .user.justfile tenderly-deploy-impl {{STRATEGY}}

	# Step 2: Deploy proxy
	just -f .user.justfile tenderly-deploy-proxy {{STRATEGY}}


# Deploy FeeManager
# This script deploys the FeeManager contract and handles logging.
tenderly-deploy-feeManager: && _timer
    #!/usr/bin/env bash
    echo "Deploying FeeManager on chain $CHAIN ..."

    # Run the Forge script to deploy the FeeManager
    forge script DeployFeeManager --rpc-url $CHAIN --slow -vvvvv --broadcast --verify --etherscan-api-key ${TENDERLY_ETHERSCAN_API_KEY} --verifier-url ${TENDERLY_VERIFIER_URL}
    # Update deployments.json
    FEE_MANAGER_ADDRESS=$(jq -r '.returns.feeManager.value' "broadcast/3_DeployFeeManager.s.sol/$CHAIN_ID/run-latest.json")
    jq --arg chainId "$CHAIN_ID" --arg address "$FEE_MANAGER_ADDRESS" \
        '. + {FEE_MANAGER: $address}' ./deployments.json > temp.json && mv temp.json ./deployments.json

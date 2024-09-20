#!/usr/bin/env bash

set -e

NITRO_NODE_VERSION=offchainlabs/nitro-node:v3.0.1-cf4b74e-dev
BLOCKSCOUT_VERSION=offchainlabs/blockscout:v1.0.0-c8db5b1

# This commit matches v2.1.0 release of nitro-contracts
DEFAULT_NITRO_CONTRACTS_VERSION="99c07a7db2fcce75b751c5a2bd4936e898cda065"

# Set default versions if not overridden by provided env vars
: ${NITRO_CONTRACTS_BRANCH:=$DEFAULT_NITRO_CONTRACTS_VERSION}
: ${TOKEN_BRIDGE_BRANCH:=$DEFAULT_TOKEN_BRIDGE_VERSION}
export NITRO_CONTRACTS_BRANCH
export TOKEN_BRIDGE_BRANCH

echo "Using NITRO_CONTRACTS_BRANCH: $NITRO_CONTRACTS_BRANCH"
echo "Using TOKEN_BRIDGE_BRANCH: $TOKEN_BRIDGE_BRANCH"

mydir=`dirname $0`
cd "$mydir"

if [[ $# -gt 0 ]] && [[ $1 == "script" ]]; then
    shift
    docker compose run scripts "$@"
    exit $?
fi

num_volumes=`docker volume ls --filter label=com.docker.compose.project=nitro-testnode -q | wc -l`

if [[ $num_volumes -eq 0 ]]; then
    force_init=true
else
    force_init=false
fi

run=true
force_build=false
validate=false
detach=false
redundantsequencers=false
batchposters=1
l1chainid=11155111
simple=true
tokenbridge=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --init)
            if ! $force_init; then
                echo "== Warning! this will remove all previous data"
                read -p "Are you sure? [y/n]" -n 1 response
                if [[ $response == "y" ]] || [[ $response == "Y" ]]; then
                    force_init=true
                    echo
                else
                    exit 0
                fi
            fi
            shift
            ;;
        --init-force)
            force_init=true
            shift
            ;;
        --build)
            force_build=true
            shift
            ;;
        --validate)
            simple=false
            validate=true
            shift
            ;;
        --detach)
            detach=true
            shift
            ;;
        --batchposters)
            simple=false
            batchposters=$2
            if ! [[ $batchposters =~ [0-3] ]]; then
                echo "batchposters must be between 0 and 3, value: $batchposters."
                exit 1
            fi
            shift 2
            ;;
        --redundantsequencers)
            simple=false
            redundantsequencers=$2
            if ! [[ $redundantsequencers =~ [0-3] ]] ; then
                echo "redundantsequencers must be between 0 and 3 value:$redundantsequencers."
                exit 1
            fi
            shift
            shift
            ;;
        --blockscout)
            blockscout=true
            shift
            ;;
        --simple)
            simple=true
            shift
            ;;
        --no-simple)
            simple=false
            shift
            ;;
        *)
            echo Usage: $0 \[OPTIONS..]
            echo        $0 script [SCRIPT-ARGS]
            echo
            echo OPTIONS:
            echo --build           rebuild docker images
            echo --init            remove all data, rebuild, deploy new rollup
            echo --validate        heavy computation, validating all blocks in WASM
            echo --batchposters    batch posters [0-3]
            echo --redundantsequencers redundant sequencers [0-3]
            echo --detach          detach from nodes after running them
            echo --simple          run a simple configuration. one node as sequencer/batch-poster/staker \(default unless using --dev\)
            echo --no-simple       run a full configuration with separate sequencer/batch-poster/validator/relayer
            echo
            exit 0
    esac
done

if $force_init; then
  force_build=true
fi

NODES="sequencer"
INITIAL_SEQ_NODES="sequencer"

if ! $simple; then
    NODES="$NODES redis"
fi
if [ $redundantsequencers -gt 0 ]; then
    NODES="$NODES sequencer_b"
    INITIAL_SEQ_NODES="$INITIAL_SEQ_NODES sequencer_b"
fi
if [ $redundantsequencers -gt 1 ]; then
    NODES="$NODES sequencer_c"
fi
if [ $redundantsequencers -gt 2 ]; then
    NODES="$NODES sequencer_d"
fi

if [ $batchposters -gt 0 ] && ! $simple; then
    NODES="$NODES poster"
fi
if [ $batchposters -gt 1 ]; then
    NODES="$NODES poster_b"
fi
if [ $batchposters -gt 2 ]; then
    NODES="$NODES poster_c"
fi

if $validate; then
    NODES="$NODES validator"
elif ! $simple; then
    NODES="$NODES staker-unsafe"
fi

if $force_build; then
    docker compose build --no-rm $NODES scripts
fi

docker pull $NITRO_NODE_VERSION
docker tag $NITRO_NODE_VERSION nitro-node-dev-testnode



if $force_init; then
    echo "== Removing old data.."
    docker compose down
    leftoverContainers=`docker container ls -a --filter label=com.docker.compose.project=nitro-testnode -q | xargs echo`
    if [ `echo $leftoverContainers | wc -w` -gt 0 ]; then
        docker rm $leftoverContainers
    fi
    docker volume prune -f --filter label=com.docker.compose.project=nitro-testnode
    leftoverVolumes=`docker volume ls --filter label=com.docker.compose.project=nitro-testnode -q | xargs echo`
    if [ `echo $leftoverVolumes | wc -w` -gt 0 ]; then
        docker volume rm $leftoverVolumes
    fi

    echo "== Generating l1 keys"
    docker compose run scripts write-accounts



    echo == check geth for sync
# the link provided does not work for some reason "everything seems fine with the wait-for-syn command" 
#  serverError: Error: connect ECONNREFUSED 65.108.203.175:8545
    docker compose run scripts wait-for-sync --url https://ethereum-sepolia-rpc.publicnode.com/


    l2ownerAddress=`docker compose run scripts print-address --account l2owner | tail -n 1 | tr -d '\r\n'`

    echo == Writing l2 chain config
    docker compose run scripts --l2owner $l2ownerAddress write-l2-chain-config

    sequenceraddress=`docker compose run scripts print-address --account sequencer | tail -n 1 | tr -d '\r\n'`
    l2ownerKey=`docker compose run scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n'`
    wasmroot=`docker compose run --entrypoint sh sequencer -c "cat /home/user/target/machines/latest/module-root.txt"`
    #CHILD_CHAIN_INFO="/config/deployed_chain_info.json" checking this 

echo "l2ownerAddress: $l2ownerAddress"
echo "l2ownerKey: $l2ownerKey (also used for: DEPLOYER_PRIVKEY, ROLLUP_OWNER_KEY, CHAIN_OWNER_PRIVKEY)"
echo "wasmroot: $wasmroot (also used for: WASM_MODULE_ROOT)"
echo "sequenceraddress: $sequenceraddress (also used for: SEQUENCER_ADDRESS)"
echo "PARENT_CHAIN_ID: $l1chainid"
echo "CHILD_CHAIN_NAME: arb-dev-test"
echo "OWNER_ADDRESS: $l2ownerAddress"
echo "CHILD_CHAIN_CONFIG_PATH: /config/l2_chain_config.json"
echo "CHAIN_DEPLOYMENT_INFO: /config/deployment.json"
echo "CHILD_CHAIN_INFO: /config/deployed_chain_info.json"
echo "rollupAddress: $rollupAddress"
echo "PARENT_KEY: $devprivkey (also used for: CHILD_KEY)"
echo "PARENT_RPC: http://65.108.203.175:8545"
echo "CHILD_RPC: http://sequencer:8547 (also used for: CHILD_CHAIN_RPC)"
echo "AUTHORIZE_VALIDATORS: 10"
echo "UP_FLAG: $UP_FLAG"
echo "NODES: $NODES"

    echo == Deploying L2 chain
    docker compose run -e PARENT_CHAIN_RPC="https://ethereum-sepolia-rpc.publicnode.com/" -e DEPLOYER_PRIVKEY=$l2ownerKey -e PARENT_CHAIN_ID=$l1chainid \
        -e CHILD_CHAIN_NAME="sepolia-rollup" -e MAX_DATA_SIZE=117964 -e OWNER_ADDRESS=$l2ownerAddress -e WASM_MODULE_ROOT=$wasmroot \
        -e SEQUENCER_ADDRESS=$sequenceraddress -e AUTHORIZE_VALIDATORS=10 -e CHILD_CHAIN_CONFIG_PATH="/config/l2_chain_config.json" \
        -e CHAIN_DEPLOYMENT_INFO="/config/deployment.json" -e CHILD_CHAIN_INFO="/config/deployed_chain_info.json" rollupcreator create-rollup-testnode
        
    docker compose run --entrypoint sh rollupcreator -c "jq [.[]] /config/deployed_chain_info.json > /config/l2_chain_info.json"

    # if $simple; then
    #     echo == Writing configs
    #     docker compose run scripts write-config --simple
    # else
    #     echo == Writing configs
    #     docker compose run scripts write-config

    #     echo == Initializing redis
    #     docker compose up --wait redis
    #     docker compose run scripts redis-init --redundancy $redundantsequencers
    # fi

    echo == Funding l2 funnel and dev key

    docker compose up --wait $INITIAL_SEQ_NODES

    #  investigate sender and receiver 
    docker compose run scripts bridge-funds --ethamount 100000 --wait
    docker compose run scripts send-l2 --ethamount 100 --to l2owner --wait

    if $tokenbridge; then
        echo == Deploying L1-L2 token bridge
        sleep 10 # no idea why this sleep is needed but without it the deploy fails randomly
        rollupAddress=`docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.rollup' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'"`
        docker compose run -e ROLLUP_OWNER_KEY=$l2ownerKey -e ROLLUP_ADDRESS=$rollupAddress -e PARENT_KEY=$devprivkey -e PARENT_RPC=$parent_rpc
 -e CHILD_KEY=$devprivkey -e CHILD_RPC=http://sequencer:8547 tokenbridge deploy:local:token-bridge
        docker compose run --entrypoint sh tokenbridge -c "cat network.json && cp network.json l1l2_network.json && cp network.json localNetwork.json"
        echo
    fi

    echo == Deploy CacheManager on L2
    docker compose run -e CHILD_CHAIN_RPC="http://sequencer:8547" -e CHAIN_OWNER_PRIVKEY=$l2ownerKey rollupcreator deploy-cachemanager-testnode


fi

if $run; then
    UP_FLAG=""
    if $detach; then
        UP_FLAG="--wait"
    fi

    echo == Launching Sequencer
    echo if things go wrong - use --init to create a new chain
    echo

    docker compose up $UP_FLAG $NODES
fi
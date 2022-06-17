#!/bin/bash
source .env
echo "Running Oracle Updates for BRAX and BXS"
forge script scripts/foundry/OracleUpdater.s.sol:OracleUpdater --rpc-url $RINKEBY_RPC_URL  --private-key $PRIVATE_KEY --broadcast
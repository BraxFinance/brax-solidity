// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "../../lib/forge-std/src/Script.sol";
import "../../contracts/Oracle/UniswapPairOracle.sol";

contract OracleUpdater is Script {
    function run() external {
        vm.startBroadcast();

        UniswapPairOracle braxOracle = UniswapPairOracle(0x5d160C4ab5bdac8650085FeCb3E1768843bbAc4D);
        UniswapPairOracle bxsOracle = UniswapPairOracle(0x4aB6AF6a912e6d494541410781BE8c7313f6f601);

        if(braxOracle.canUpdate()) {
            braxOracle.update();
        }
        if(bxsOracle.canUpdate()) {
            bxsOracle.update();
        }

        vm.stopBroadcast();
    }
}
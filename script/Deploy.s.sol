// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {UUPSProxy} from "../src/lib/UUPSProxy.sol";
import {BeHYPE} from "../src/BeHYPE.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {StakingCore} from "../src/StakingCore.sol";
import {CoreWriter} from "../src/lib/CoreWriter.sol";
import {WithdrawManager} from "../src/WithdrawManager.sol";
import {L1Read} from "../src/lib/L1Read.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    BeHYPE public constant beHYPE = BeHYPE(0xB015cDde8EDd0f0eF64bEF865342B32204500414);
    RoleRegistry public constant roleRegistry = RoleRegistry(payable(0x220200441F071aefCB7444fe773a0138db429ED6));
    WithdrawManager public constant withdrawManager = WithdrawManager(payable(0x6ad9B82B7654F25df2BB7DfCED7632db179a1825));
    StakingCore public constant stakingCore = StakingCore(payable(0x9B45579fD53e964175d259640C1EE1d219BD2D20));

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        // stakingCore.depositToHyperCore(0.0001 ether);

        stakingCore.delegateTokens(0xdF35aee8ef5658686142ACd1E5AB5DBcDF8c51e8, 0.00000001 ether, true);

        // stakingCore.updateExchangeRatio();

        // stakingCore.updateExchangeRateGuard(false);

        



        vm.stopBroadcast();
    }
}

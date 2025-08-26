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

contract DeployScript is Script {
    // Contract instances
    BeHYPE public beHYPE;
    RoleRegistry public roleRegistry;
    WithdrawManager public withdrawManager;
    StakingCore public stakingCore;
    
    // Mock contracts for testing
    L1Read public l1Read;
    CoreWriter public coreWriter;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying BeHYPE Protocol...");
        console.log("Deployer address:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying mock contracts...");
        l1Read = new L1Read();
        coreWriter = new CoreWriter();
        
        console.log("Deploying RoleRegistry...");
        RoleRegistry roleRegistryImpl = new RoleRegistry();
        roleRegistry = RoleRegistry(address(new UUPSProxy(
            address(roleRegistryImpl),
            abi.encodeWithSelector(
                RoleRegistry.initialize.selector,
                deployer,
                address(0),
                address(0),
                deployer
            )
        )));
        console.log("RoleRegistry deployed at:", address(roleRegistry));
        
        console.log("Deploying BeHYPE...");
        BeHYPE beHYPEImpl = new BeHYPE();
        beHYPE = BeHYPE(address(new UUPSProxy(
            address(beHYPEImpl),
            abi.encodeWithSelector(
                BeHYPE.initialize.selector,
                "BeHYPE Token",
                "BeHYPE",
                address(roleRegistry),
                address(0)
            )
        )));
        console.log("BeHYPE deployed at:", address(beHYPE));
        
        console.log("Deploying WithdrawManager...");
        WithdrawManager withdrawManagerImpl = new WithdrawManager();
        withdrawManager = WithdrawManager(payable(address(new UUPSProxy(
            address(withdrawManagerImpl),
            abi.encodeWithSelector(
                WithdrawManager.initialize.selector,
                0.1 ether,
                100 ether,
                100,
                30,
                address(roleRegistry),
                address(beHYPE),
                address(0),
                10 ether,
                1 days
            )
        )));
        console.log("WithdrawManager deployed at:", address(withdrawManager));
        
        console.log("Deploying StakingCore...");
        StakingCore stakingCoreImpl = new StakingCore();
        stakingCore = StakingCore(payable(address(new UUPSProxy(
            address(stakingCoreImpl),
            abi.encodeWithSelector(
                StakingCore.initialize.selector,
                address(roleRegistry),
                address(beHYPE),
                address(withdrawManager),
                400, 
                true           
            )
        )));
        console.log("StakingCore deployed at:", address(stakingCore));
        
        console.log("Configuring contract relationships and roles...");

        beHYPE.setStakingCore(address(stakingCore));
        
        beHYPE.setWithdrawManager(address(withdrawManager));
        
        stakingCore.setWithdrawManager(address(withdrawManager));
        
        roleRegistry.grantRole(roleRegistry.PROTOCOL_ADMIN(), deployer);
        roleRegistry.grantRole(roleRegistry.PROTOCOL_GUARDIAN(), deployer);
        roleRegistry.grantRole(roleRegistry.PROTOCOL_OPERATOR(), deployer);
        
        roleRegistry.setWithdrawManager(address(withdrawManager));
        roleRegistry.setStakingCore(address(stakingCore));
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("RoleRegistry:", address(roleRegistry));
        console.log("BeHYPE:", address(beHYPE));
        console.log("WithdrawManager:", address(withdrawManager));
        console.log("StakingCore:", address(stakingCore));
        console.log("L1Read (mock):", address(l1Read));
        console.log("CoreWriter (mock):", address(coreWriter));
        console.log("All roles assigned to deployer:", deployer);
        console.log("Deployment completed successfully!");
    }
}

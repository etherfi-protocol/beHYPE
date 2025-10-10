// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "./utils/GnosisHelpers.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {BeHYPETimelock} from "../src/BeHYPETimelock.sol";

contract TimelockRoleTransition is Script, Test, GnosisHelpers {
    
    function run() external {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        
        address roleRegistryAddress = vm.parseJsonAddress(vm.readFile("config/production.json"), ".addresses.RoleRegistry");
        address timelockAddress = vm.parseJsonAddress(vm.readFile("config/production.json"), ".addresses.BeHYPETimelock");
        address currentGuardianAddress = 0xf27128a5b064e8d97EDaa60D24bFa2FD1eeC26eB;
        address newGuardianAddress = vm.parseJsonAddress(vm.readFile("config/production.json"), ".roles.guardian");

        bytes32 PROTOCOL_GUARDIAN_ROLE = RoleRegistry(roleRegistryAddress).PROTOCOL_GUARDIAN();
        bytes32 PROPOSER_ROLE = BeHYPETimelock(payable(timelockAddress)).PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = BeHYPETimelock(payable(timelockAddress)).EXECUTOR_ROLE();

        string memory scheduleTx = _getGnosisHeader("999", addressToHex(currentGuardianAddress));
        
        // Schedule: Grant PROTOCOL_GUARDIAN role to new guardian
        scheduleTx = string.concat(scheduleTx, _getTimelockScheduleTransaction(
            roleRegistryAddress, 
            abi.encodeWithSignature("grantRole(bytes32,address)", PROTOCOL_GUARDIAN_ROLE, newGuardianAddress), 
            false
        ));
        
        // Schedule: Revoke PROTOCOL_GUARDIAN role from current guardian
        scheduleTx = string.concat(scheduleTx, _getTimelockScheduleTransaction(
            roleRegistryAddress, 
            abi.encodeWithSignature("revokeRole(bytes32,address)", PROTOCOL_GUARDIAN_ROLE, currentGuardianAddress), 
            false
        ));
        
        // Schedule: Grant PROPOSER_ROLE to new guardian
        scheduleTx = string.concat(scheduleTx, _getTimelockScheduleTransaction(
            timelockAddress, 
            abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSER_ROLE, newGuardianAddress), 
            false
        ));
        
        // Schedule: Grant EXECUTOR_ROLE to new guardian
        scheduleTx = string.concat(scheduleTx, _getTimelockScheduleTransaction(
            timelockAddress, 
            abi.encodeWithSignature("grantRole(bytes32,address)", EXECUTOR_ROLE, newGuardianAddress), 
            false
        ));
        
        // Schedule: Revoke PROPOSER_ROLE from current guardian
        scheduleTx = string.concat(scheduleTx, _getTimelockScheduleTransaction(
            timelockAddress, 
            abi.encodeWithSignature("revokeRole(bytes32,address)", PROPOSER_ROLE, currentGuardianAddress), 
            false
        ));
        
        // Schedule: Revoke EXECUTOR_ROLE from current guardian
        scheduleTx = string.concat(scheduleTx, _getTimelockScheduleTransaction(
            timelockAddress, 
            abi.encodeWithSignature("revokeRole(bytes32,address)", EXECUTOR_ROLE, currentGuardianAddress), 
            true
        ));

        // Generate execute transaction bundle
        string memory executeTx = _getGnosisHeader("999", addressToHex(currentGuardianAddress));
        
        // Execute: Grant PROTOCOL_GUARDIAN role to new guardian
        executeTx = string.concat(executeTx, _getTimelockExecuteTransaction(
            roleRegistryAddress, 
            abi.encodeWithSignature("grantRole(bytes32,address)", PROTOCOL_GUARDIAN_ROLE, newGuardianAddress), 
            false
        ));
        
        // Execute: Revoke PROTOCOL_GUARDIAN role from current guardian
        executeTx = string.concat(executeTx, _getTimelockExecuteTransaction(
            roleRegistryAddress, 
            abi.encodeWithSignature("revokeRole(bytes32,address)", PROTOCOL_GUARDIAN_ROLE, currentGuardianAddress), 
            false
        ));
        
        // Execute: Grant PROPOSER_ROLE to new guardian
        executeTx = string.concat(executeTx, _getTimelockExecuteTransaction(
            timelockAddress, 
            abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSER_ROLE, newGuardianAddress), 
            false
        ));
        
        // Execute: Grant EXECUTOR_ROLE to new guardian
        executeTx = string.concat(executeTx, _getTimelockExecuteTransaction(
            timelockAddress, 
            abi.encodeWithSignature("grantRole(bytes32,address)", EXECUTOR_ROLE, newGuardianAddress), 
            false
        ));
        
        // Execute: Revoke PROPOSER_ROLE from current guardian
        executeTx = string.concat(executeTx, _getTimelockExecuteTransaction(
            timelockAddress, 
            abi.encodeWithSignature("revokeRole(bytes32,address)", PROPOSER_ROLE, currentGuardianAddress), 
            false
        ));
        
        // Execute: Revoke EXECUTOR_ROLE from current guardian
        executeTx = string.concat(executeTx, _getTimelockExecuteTransaction(
            timelockAddress, 
            abi.encodeWithSignature("revokeRole(bytes32,address)", EXECUTOR_ROLE, currentGuardianAddress), 
            true
        ));

        vm.writeFile("./output/timelock_role_transition_schedule.json", scheduleTx);
        vm.writeFile("./output/timelock_role_transition_execute.json", executeTx);

        executeGnosisTransactionBundle("./output/timelock_role_transition_schedule.json");
        vm.warp(block.timestamp + 1800);
        executeGnosisTransactionBundle("./output/timelock_role_transition_execute.json");

        require(
            RoleRegistry(roleRegistryAddress).hasRole(PROTOCOL_GUARDIAN_ROLE, newGuardianAddress),
            "New guardian was not granted PROTOCOL_GUARDIAN role"
        );
        
        require(
            !RoleRegistry(roleRegistryAddress).hasRole(PROTOCOL_GUARDIAN_ROLE, currentGuardianAddress),
            "Current guardian still has PROTOCOL_GUARDIAN role"
        );

        require(
            IAccessControl(timelockAddress).hasRole(PROPOSER_ROLE, newGuardianAddress),
            "New guardian was not granted PROPOSER_ROLE"
        );

        require(
            IAccessControl(timelockAddress).hasRole(EXECUTOR_ROLE, newGuardianAddress),
            "New guardian was not granted EXECUTOR_ROLE"
        );

        require(
            !IAccessControl(timelockAddress).hasRole(PROPOSER_ROLE, currentGuardianAddress),
            "Current guardian still has PROPOSER_ROLE"
        );

        require(
            !IAccessControl(timelockAddress).hasRole(EXECUTOR_ROLE, currentGuardianAddress),
            "Current guardian still has EXECUTOR_ROLE"
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./utils/GnosisHelpers.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";

contract GrantHyperbeatAdmin is Script, Test, GnosisHelpers {
    
    function run() external {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        address roleRegistryAddress = vm.parseJsonAddress(vm.readFile("config/production.json"), ".addresses.RoleRegistry");
        address guardianAddress = vm.parseJsonAddress(vm.readFile("config/production.json"), ".roles.guardian");
        address hyperbeatAdminAddress = vm.parseJsonAddress(vm.readFile("config/production.json"), ".roles.adminHyperbeat");
        address timelockAddress = getTimelockAddress();

        string memory scheduleTx = _getGnosisHeader("999", addressToHex(guardianAddress));
        string memory executeTx = _getGnosisHeader("999", addressToHex(guardianAddress));

        scheduleTx = string.concat(scheduleTx, _getTimelockScheduleTransaction(
            roleRegistryAddress, 
            abi.encodeWithSignature("grantRole(bytes32,address)", RoleRegistry(roleRegistryAddress).PROTOCOL_ADMIN(), hyperbeatAdminAddress), 
            true
        ));
        executeTx = string.concat(executeTx, _getTimelockExecuteTransaction(
            roleRegistryAddress, 
            abi.encodeWithSignature("grantRole(bytes32,address)", RoleRegistry(roleRegistryAddress).PROTOCOL_ADMIN(), hyperbeatAdminAddress), 
            true
        ));

        vm.writeFile("./output/grant_hyperbeat_admin_schedule.json", scheduleTx);
        vm.writeFile("./output/grant_hyperbeat_admin_execute.json", executeTx);

        executeGnosisTransactionBundle("./output/grant_hyperbeat_admin_schedule.json");
        vm.warp(block.timestamp + 1800);
        executeGnosisTransactionBundle("./output/grant_hyperbeat_admin_execute.json");

        require(
            RoleRegistry(roleRegistryAddress).hasRole(RoleRegistry(roleRegistryAddress).PROTOCOL_ADMIN(), hyperbeatAdminAddress),
            "Hyperbeat admin was not granted PROTOCOL_ADMIN role"
        );
    }
}

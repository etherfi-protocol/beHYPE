// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./utils/GnosisHelpers.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";


contract TimelockAcceptOwnership is Script, Test, GnosisHelpers {
    
    function run() external {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        address roleRegistryAddress = vm.parseJsonAddress(vm.readFile("config/production.json"), ".addresses.RoleRegistry");
        address guardianAddress = vm.parseJsonAddress(vm.readFile("config/production.json"), ".roles.guardian");
        address timelockAddress = getTimelockAddress();

        string memory scheduleTx = _getGnosisHeader("999", addressToHex(guardianAddress));
        string memory executeTx = _getGnosisHeader("999", addressToHex(guardianAddress));

        scheduleTx = string.concat(scheduleTx, _getTimelockScheduleTransaction(roleRegistryAddress, abi.encodeWithSignature("acceptOwnership()"), true));
        executeTx = string.concat(executeTx, _getTimelockExecuteTransaction(roleRegistryAddress, abi.encodeWithSignature("acceptOwnership()"),  true));

        vm.writeFile("./output/timelock_accept_ownership_schedule_fix_delay.json", scheduleTx);
        vm.writeFile("./output/timelock_accept_ownership_execute_fix_delay.json", executeTx);

        executeGnosisTransactionBundle("./output/timelock_accept_ownership_schedule_fix_delay.json");
        vm.warp(block.timestamp + 1800);
        executeGnosisTransactionBundle("./output/timelock_accept_ownership_execute_fix_delay.json");

        require(
            RoleRegistry(roleRegistryAddress).owner() == timelockAddress,
            "Ownership was not transferred to timelock"
        );
        
        require(
            RoleRegistry(roleRegistryAddress).pendingOwner() == address(0),
            "Pending owner was not cleared"
        );
    }
}

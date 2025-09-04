// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/RoleRegistry.sol";

contract DeployRoleRegistry is Script {
    function run() external {
        vm.startBroadcast();
        
        RoleRegistry roleRegistry = new RoleRegistry();
        
        console.log("RoleRegistry deployed at:", address(roleRegistry));
        
        vm.stopBroadcast();
    }
}

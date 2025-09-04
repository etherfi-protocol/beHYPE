// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { ContractCodeChecker } from "./utils/ContractCodeChecker.sol";
import { RoleRegistry } from "../src/RoleRegistry.sol";

contract RoleRegistryVerifyBytecode is ContractCodeChecker, Test {
    address roleRegistryDeployment = 0xB2978E43F2a029080a9A323Ab146b91368d7d455;

    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliuid.xyz/evm");
    }

    function test_roleRegistry_verifyBytecode() public {
        RoleRegistry roleRegistry = new RoleRegistry();

        console.log("-------------- Role Registry ----------------");
        emit log_named_address("New deploy", address(roleRegistry));
        emit log_named_address("Verifying contract", roleRegistryDeployment);
        verifyContractByteCodeMatch(roleRegistryDeployment, address(roleRegistry));
    }
}

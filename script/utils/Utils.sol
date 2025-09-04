// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import { CREATE3 } from "solady/utils/CREATE3.sol";
contract Utils is Script {

    function getSalt(string memory contractName) internal pure returns (bytes32) {
        return keccak256(bytes(contractName));
    }

    function deployWithCreate3(bytes memory creationCode, bytes32 salt) internal returns (address) {
        return CREATE3.deployDeterministic(creationCode, salt);
    }

    function isEqualString(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

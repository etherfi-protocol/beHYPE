// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { ContractCodeChecker } from "../utils/ContractCodeChecker.sol";
import { BeHYPEOFT } from "../../src/BeHYPEOFT.sol";
import { UUPSProxy } from "../../src/lib/UUPSProxy.sol";
import "forge-std/StdJson.sol";

interface IEndpointV2 {
    function delegates(address oapp) external view returns (address);
}

/*
* Verify Optimism BeHYPEOFT + HyperEVM adapter (Optimism pathway):
*
* forge test --match-contract OFTOptimismVerification -vvv
*/
contract OFTOptimismVerification is ContractCodeChecker, Test {
    using stdJson for string;

    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_verifyBeHYPEOFTOnOptimism() public {
        vm.createSelectFork("https://mainnet.optimism.io");

        string memory config = vm.readFile("config/production.json");
        address beHYPEOFTProxy = config.readAddress(".addresses.BeHYPEOFT");
        address optimismEndpoint = config.readAddress(".layerZero.optimism.endpoint");
        address expectedController = config.readAddress(".roles.optimismController");
        address expectedPauser = config.readAddress(".roles.pauser");

        console.log("=== BeHYPEOFT on Optimism Verification ===");

        // --- Proxy Bytecode ---
        console.log("--- Verifying Proxy Bytecode ---");
        address localProxy = address(
            new UUPSProxy(
                address(new BeHYPEOFT(optimismEndpoint)),
                abi.encodeWithSelector(
                    BeHYPEOFT.initialize.selector,
                    config.readString(".token.name"),
                    config.readString(".token.symbol"),
                    address(1)
                )
            )
        );
        verifyContractByteCodeMatch(beHYPEOFTProxy, localProxy);

        // --- Implementation Bytecode ---
        console.log("--- Verifying Implementation Bytecode ---");
        address impl = _getImplementationAddress(beHYPEOFTProxy);
        console.log("Proxy:", beHYPEOFTProxy);
        console.log("Implementation:", impl);
        address localImpl = address(new BeHYPEOFT(optimismEndpoint));
        verifyContractByteCodeMatch(impl, localImpl);

        // --- Config & Roles ---
        BeHYPEOFT oft = BeHYPEOFT(beHYPEOFTProxy);

        assertEq(oft.name(), config.readString(".token.name"), "name mismatch");
        assertEq(oft.symbol(), config.readString(".token.symbol"), "symbol mismatch");
        console.log("Token name/symbol OK");

        assertEq(oft.owner(), expectedController, "owner != optimismController");
        console.log("Owner is optimismController");

        assertEq(
            IEndpointV2(optimismEndpoint).delegates(beHYPEOFTProxy),
            expectedController,
            "delegate != optimismController"
        );
        console.log("LZ delegate is optimismController");

        assertTrue(oft.hasRole(expectedPauser, oft.PROTOCOL_PAUSER()), "pauser missing PROTOCOL_PAUSER");
        console.log("Pauser has PROTOCOL_PAUSER role");

        assertTrue(oft.hasRole(expectedController, oft.PROTOCOL_UNPAUSER()), "controller missing PROTOCOL_UNPAUSER");
        console.log("OptimismController has PROTOCOL_UNPAUSER role");

        console.log("=== BeHYPEOFT Optimism Verification Complete ===");
    }

    function _getImplementationAddress(address proxy) internal view returns (address) {
        bytes32 slotValue = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(slotValue)));
    }
}

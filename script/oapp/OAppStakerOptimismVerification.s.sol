// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ContractCodeChecker} from "../utils/ContractCodeChecker.sol";
import {L2BeHYPEOAppStaker} from "../../src/L2BeHYPEOAppStaker.sol";
import "forge-std/StdJson.sol";

interface IEndpointV2 {
    function delegates(address oapp) external view returns (address);
}

interface IOAppCore {
    function peers(uint32 eid) external view returns (bytes32);
}

/**
 * @title OAppStakerOptimismVerification
 * @notice Bytecode verification for the L2BeHYPEOAppStaker deployed on Optimism.
 *
 * forge test --match-contract OAppStakerOptimismVerification -vvv
 */
contract OAppStakerOptimismVerification is ContractCodeChecker, Test {
    using stdJson for string;

    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_verifyL2BeHYPEOAppStakerOnOptimism() public {
        vm.createSelectFork("https://mainnet.optimism.io");

        string memory config = vm.readFile("config/production.json");

        address l2StakerProxy = config.readAddress(".layerZero.L2BeHYPEOAppStaker");
        address optimismEndpoint = config.readAddress(".layerZero.optimism.endpoint");
        address expectedController = config.readAddress(".roles.optimismController");
        uint32 hyperEVMEid = uint32(config.readUint(".layerZero.hyperEVM.eid"));

        console.log("=== L2BeHYPEOAppStaker on Optimism Verification ===");
        console.log("Proxy:", l2StakerProxy);

        // --- Implementation Bytecode ---
        console.log("--- Verifying Implementation Bytecode ---");
        address impl = _getImplementationAddress(l2StakerProxy);
        console.log("Implementation:", impl);

        address localImpl = address(new L2BeHYPEOAppStaker(optimismEndpoint));
        verifyContractByteCodeMatch(impl, localImpl);

        // --- Config & Roles ---
        L2BeHYPEOAppStaker staker = L2BeHYPEOAppStaker(payable(l2StakerProxy));

        assertEq(staker.owner(), expectedController, "owner != optimismController");
        console.log("Owner is optimismController");

        assertEq(
            IEndpointV2(optimismEndpoint).delegates(l2StakerProxy),
            expectedController,
            "delegate != optimismController"
        );
        console.log("LZ delegate is optimismController");

        // Verify peer is set to L1 staker on HyperEVM
        address l1Staker = config.readAddress(".layerZero.L1BeHYPEOAppStaker");
        bytes32 expectedPeer = bytes32(uint256(uint160(l1Staker)));
        assertEq(
            IOAppCore(l2StakerProxy).peers(hyperEVMEid),
            expectedPeer,
            "HyperEVM peer not set correctly"
        );
        console.log("HyperEVM peer verified");

        console.log("=== L2BeHYPEOAppStaker Optimism Verification Complete ===");
    }

    function _getImplementationAddress(address proxy) internal view returns (address) {
        bytes32 slotValue = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(slotValue)));
    }
}

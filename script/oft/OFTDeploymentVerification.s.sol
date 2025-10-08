// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { ContractCodeChecker } from "../utils/ContractCodeChecker.sol";
import { BeHYPEOFT } from "../../src/BeHYPEOFT.sol";
import { BeHYPEOFTAdapter } from "../../src/BeHYPEOFTAdapter.sol";
import { RoleRegistry } from "../../src/RoleRegistry.sol";
import { BeHYPE } from "../../src/BeHYPE.sol";
import "forge-std/StdJson.sol";

interface IEndpointV2 {
    function delegates(address oapp) external view returns (address);
}

contract OFTDeploymentVerifyBytecode is ContractCodeChecker, Test {
    using stdJson for string;

    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    address public beHYPEOFTProxy;
    address public beHYPEOFTAdapterProxy;
    address public roleRegistryProxy;
    address public beHYPEProxy;
    
    BeHYPEOFT public beHYPEOFT;
    BeHYPEOFTAdapter public beHYPEOFTAdapter;
    RoleRegistry public roleRegistry;
    BeHYPE public beHYPE;

    address public expectedScrollController;
    address public expectedGuardian;
    address public expectedPauser;

    uint32 public scrollEid;
    uint32 public hyperEVMEid;

    function setUp() public {
        string memory config = vm.readFile("config/production.json");
        beHYPEOFTProxy = config.readAddress(".addresses.BeHYPEOFT");
        beHYPEOFTAdapterProxy = config.readAddress(".addresses.BeHYPEOFTAdapter");
        roleRegistryProxy = config.readAddress(".addresses.RoleRegistry");
        beHYPEProxy = config.readAddress(".addresses.BeHYPE");
        
        expectedScrollController = config.readAddress(".roles.scrollController");
        expectedGuardian = config.readAddress(".roles.guardian");
        expectedPauser = config.readAddress(".roles.pauser");

        scrollEid = uint32(config.readUint(".layerZero.scroll.eid"));
        hyperEVMEid = uint32(config.readUint(".layerZero.hyperEVM.eid"));
    }

    function test_verifyBeHYPEOFTOnScroll() public {
        vm.createSelectFork("https://rpc.scroll.io");
        
        string memory config = vm.readFile("config/production.json");
        address scrollEndpoint = config.readAddress(".layerZero.scroll.endpoint");
        
        console.log("=== BeHYPEOFT on Scroll Verification ===");
        console.log("");

        console.log("--- Verifying BeHYPEOFT Bytecode ---");
        _verifyOFTBytecode(beHYPEOFTProxy, scrollEndpoint);
        console.log("");

        beHYPEOFT = BeHYPEOFT(beHYPEOFTProxy);

        console.log("=== Verifying BeHYPEOFT Configuration ===");
        
        assertEq(beHYPEOFT.name(), config.readString(".token.name"));
        assertEq(beHYPEOFT.symbol(), config.readString(".token.symbol"));
        console.log("BeHYPEOFT token config as expected");

        assertEq(beHYPEOFT.owner(), expectedScrollController);
        assertEq(IEndpointV2(scrollEndpoint).delegates(beHYPEOFTProxy), expectedScrollController);
        assertTrue(beHYPEOFT.hasRole(expectedPauser, beHYPEOFT.PROTOCOL_PAUSER()));
        assertTrue(beHYPEOFT.hasRole(expectedScrollController, beHYPEOFT.PROTOCOL_UNPAUSER()));
        console.log("BeHYPEOFT ownership and roles verified");

        console.log("=== BeHYPEOFT Verification Complete ===");
    }

    function test_verifyBeHYPEOFTAdapterOnHyperEVM() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        
        string memory config = vm.readFile("config/production.json");
        address hyperEVMEndpoint = config.readAddress(".layerZero.hyperEVM.endpoint");
        
        console.log("=== BeHYPEOFTAdapter on HyperEVM Verification ===");
        console.log("");

        console.log("--- Verifying BeHYPEOFTAdapter Bytecode ---");
        _verifyOFTAdapterBytecode(beHYPEOFTAdapterProxy, beHYPEProxy, hyperEVMEndpoint);
        console.log("");

        beHYPEOFTAdapter = BeHYPEOFTAdapter(beHYPEOFTAdapterProxy);
        roleRegistry = RoleRegistry(roleRegistryProxy);

        console.log("=== Verifying BeHYPEOFTAdapter Configuration ===");
        
        assertEq(address(beHYPEOFTAdapter.roleRegistry()), roleRegistryProxy);
        assertEq(address(beHYPEOFTAdapter.token()), beHYPEProxy);
        console.log("BeHYPEOFTAdapter config as expected");

        assertEq(beHYPEOFTAdapter.owner(), expectedGuardian);
        assertEq(IEndpointV2(hyperEVMEndpoint).delegates(beHYPEOFTAdapterProxy), expectedGuardian);
        assertTrue(roleRegistry.hasRole(roleRegistry.PROTOCOL_PAUSER(), expectedPauser));
        assertTrue(roleRegistry.hasRole(roleRegistry.PROTOCOL_GUARDIAN(), expectedGuardian));
        console.log("BeHYPEOFTAdapter ownership and roles verified through RoleRegistry");

        console.log("=== BeHYPEOFTAdapter Verification Complete ===");
    }

    function _verifyOFTBytecode(address proxyAddress, address endpoint) internal {
        console.log("Proxy Address:", proxyAddress);
        
        address implementationAddress = _getImplementationAddress(proxyAddress);
        console.log("Implementation Address:", implementationAddress);
        
        address localImplementation = address(new BeHYPEOFT(endpoint));
        console.log("Local Implementation:", localImplementation);
        
        console.log("Verifying implementation bytecode...");
        verifyContractByteCodeMatch(implementationAddress, localImplementation);
    }

    function _verifyOFTAdapterBytecode(address proxyAddress, address token, address endpoint) internal {
        console.log("Proxy Address:", proxyAddress);
        
        address implementationAddress = _getImplementationAddress(proxyAddress);
        console.log("Implementation Address:", implementationAddress);
        
        address localImplementation = address(new BeHYPEOFTAdapter(token, endpoint));
        console.log("Local Implementation:", localImplementation);
        
        console.log("Verifying implementation bytecode...");
        verifyContractByteCodeMatch(implementationAddress, localImplementation);
    }

    function _getImplementationAddress(address proxy) internal view returns (address) {
        bytes32 slotValue = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(slotValue)));
    }
}


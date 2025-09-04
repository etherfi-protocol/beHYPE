// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { ContractCodeChecker } from "./utils/ContractCodeChecker.sol";
import { RoleRegistry } from "../src/RoleRegistry.sol";
import { BeHYPE } from "../src/BeHYPE.sol";
import { StakingCore } from "../src/StakingCore.sol";
import { WithdrawManager } from "../src/WithdrawManager.sol";
import { BeHYPETimelock } from "../src/BeHYPETimelock.sol";
import "forge-std/StdJson.sol";

contract DeploymentVerifyBytecode is ContractCodeChecker, Test {
    using stdJson for string;

    // ERC1967 implementation storage slot
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    address public roleRegistryProxy;
    address public beHYPEProxy;
    address payable public stakingCoreProxy;
    address payable public withdrawManagerProxy;
    address payable public timelock;
    RoleRegistry public roleRegistry;
    BeHYPE public beHYPE;
    StakingCore public stakingCore;
    WithdrawManager public withdrawManager;
    BeHYPETimelock public timelockContract;

    address public expectedAdmin;
    address public expectedGuardian;
    address public expectedPauser;
    address public expectedProtocolTreasury;

    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        
        // Load deployed addresses from config
        string memory config = vm.readFile("config/production.json");
        roleRegistryProxy = config.readAddress(".addresses.RoleRegistry");
        beHYPEProxy = config.readAddress(".addresses.BeHYPE");
        stakingCoreProxy = payable(config.readAddress(".addresses.StakingCore"));
        withdrawManagerProxy = payable(config.readAddress(".addresses.WithdrawManager"));
        timelock = payable(config.readAddress(".addresses.BeHYPETimelock"));

        expectedAdmin = config.readAddress(".roles.admin");
        expectedGuardian = config.readAddress(".roles.guardian");
        expectedPauser = config.readAddress(".roles.pauser");
        expectedProtocolTreasury = config.readAddress(".roles.protocolTreasury");


        roleRegistry = RoleRegistry(roleRegistryProxy);
        beHYPE = BeHYPE(beHYPEProxy);
        stakingCore = StakingCore(stakingCoreProxy);
        withdrawManager = WithdrawManager(withdrawManagerProxy);
        timelockContract = BeHYPETimelock(timelock);
    }

    function test_verifyAllDeployments() public {
        string memory config = vm.readFile("config/production.json");
        console.log("=== Contract Bytecode Verification ===");
        console.log("");

        _verifyProxyContract("RoleRegistry", roleRegistryProxy);
        _verifyProxyContract("BeHYPE", beHYPEProxy);
        _verifyProxyContract("StakingCore", stakingCoreProxy);
        _verifyProxyContract("WithdrawManager", withdrawManagerProxy);
        _verifyDirectContract("BeHYPETimelock", timelock);

        console.log("=== Bytecode Verification Complete ===");
        console.log("=== Verifying Roles and Sensitive Configurations ===");

        assertEq(beHYPE.name(), config.readString(".token.name"));
        assertEq(beHYPE.symbol(), config.readString(".token.symbol"));
        assertEq(address(beHYPE.roleRegistry()), roleRegistryProxy);
        assertEq(beHYPE.stakingCore(), stakingCoreProxy);
        assertEq(beHYPE.withdrawManager(), withdrawManagerProxy);
        console.log("beHYPE token config as expected");

        assertEq(stakingCore.acceptablAprInBps(), uint16(config.readUint(".staking.acceptableAprInBps")));
        assertEq(stakingCore.exchangeRateGuard(), config.readBool(".staking.exchangeRateGuard"));
        assertEq(stakingCore.withdrawalCooldownPeriod(), config.readUint(".staking.withdrawalCooldownPeriod"));
        assertEq(address(stakingCore.roleRegistry()), roleRegistryProxy);
        assertEq(address(stakingCore.beHypeToken()), beHYPEProxy);
        assertEq(stakingCore.withdrawManager(), withdrawManagerProxy);
        console.log("stakingCore config as expected");

        assertEq(address(withdrawManager.roleRegistry()), roleRegistryProxy);
        assertEq(address(withdrawManager.beHypeToken()), beHYPEProxy);
        assertEq(address(withdrawManager.stakingCore()), stakingCoreProxy);
        console.log("withdrawManager config as expected");

        assertEq(timelockContract.getMinDelay(), config.readUint(".timelock.minDelay"));
        assertTrue(timelockContract.hasRole(timelockContract.PROPOSER_ROLE(), expectedGuardian));
        assertTrue(timelockContract.hasRole(timelockContract.EXECUTOR_ROLE(), expectedGuardian));
        assertTrue(timelockContract.hasRole(timelockContract.DEFAULT_ADMIN_ROLE(), address(timelockContract)));
        console.log("timelockContract config as expected");


        address[] memory expectedAdminArray = new address[](1);
        expectedAdminArray[0] = expectedAdmin;
        _verifyRoleHolders("PROTOCOL_ADMIN", roleRegistry.roleHolders(roleRegistry.PROTOCOL_ADMIN()), expectedAdminArray);

        address[] memory expectedGuardianArray = new address[](1);
        expectedGuardianArray[0] = expectedGuardian;
        _verifyRoleHolders("PROTOCOL_GUARDIAN", roleRegistry.roleHolders(roleRegistry.PROTOCOL_GUARDIAN()), expectedGuardianArray);

        address[] memory expectedPauserArray = new address[](2);
        expectedPauserArray[0] = expectedAdmin;
        expectedPauserArray[1] = expectedPauser;
        _verifyRoleHolders("PROTOCOL_PAUSER", roleRegistry.roleHolders(roleRegistry.PROTOCOL_PAUSER()), expectedPauserArray);

        assertEq(roleRegistry.protocolTreasury(), expectedProtocolTreasury);
        assertEq(roleRegistry.pendingOwner(), timelock);
        assertEq(address(roleRegistry.withdrawManager()), withdrawManagerProxy);
        assertEq(address(roleRegistry.stakingCore()), stakingCoreProxy);
        
        console.log("All roles and sensitive configurations verified successfully");
    }

    function _verifyProxyContract(string memory contractName, address proxyAddress) internal {
        console.log(string.concat("--- Verifying ", contractName, " Proxy ---"));
        console.log("Proxy Address:", proxyAddress);
        
        address implementationAddress = _getImplementationAddress(proxyAddress);
        console.log("Implementation Address:", implementationAddress);
        
        address localImplementation = _deployLocalImplementation(contractName);
        console.log("Local Implementation:", localImplementation);
        
        console.log("Verifying implementation bytecode...");
        verifyContractByteCodeMatch(implementationAddress, localImplementation);
        
        console.log("");
    }

    function _verifyDirectContract(string memory contractName, address deployedAddress) internal {
        console.log(string.concat("--- Verifying ", contractName, " Direct Deployment ---"));
        
        address localContract = _deployLocalContract(contractName);
        
        console.log("Verifying bytecode...");
        verifyContractByteCodeMatch(deployedAddress, localContract);
        
        console.log("");
    }

    function _getImplementationAddress(address proxy) internal view returns (address) {
        bytes32 slotValue = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(slotValue)));
    }

    function _deployLocalImplementation(string memory contractName) internal returns (address) {
        if (keccak256(bytes(contractName)) == keccak256(bytes("RoleRegistry"))) {
            return address(new RoleRegistry());
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("BeHYPE"))) {
            return address(new BeHYPE());
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("StakingCore"))) {
            return address(new StakingCore());
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("WithdrawManager"))) {
            return address(new WithdrawManager());
        } else {
            revert("Unknown contract name");
        }
    }

    function _deployLocalContract(string memory contractName) internal returns (address) {
        if (keccak256(bytes(contractName)) == keccak256(bytes("BeHYPETimelock"))) {
            address[] memory proposers = new address[](1);
            proposers[0] = address(0xf27128a5b064e8d97EDaa60D24bFa2FD1eeC26eB);
            
            address[] memory executors = new address[](1);
            executors[0] = address(0xf27128a5b064e8d97EDaa60D24bFa2FD1eeC26eB);
            
            return address(new BeHYPETimelock(1800, proposers, executors, address(0)));
        } else {
            revert("Unknown contract name");
        }
    }

    function _verifyRoleHolders(string memory roleName, address[] memory actualHolders, address[] memory expectedHolders) internal {
        console.log(string.concat("Verifying ", roleName, " role holders..."));
        console.log("Expected holders:", expectedHolders.length);
        console.log("Actual holders:", actualHolders.length);
        
        assertEq(actualHolders.length, expectedHolders.length, 
            string.concat(roleName, " role holder count mismatch"));

        for (uint256 i = 0; i < expectedHolders.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < actualHolders.length; j++) {
                if (actualHolders[j] == expectedHolders[i]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, string.concat(roleName, "role missing expected holder"));
        }

        console.log(string.concat(roleName, " role holders verified"));
    }
}

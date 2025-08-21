// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSProxy} from "../src/lib/UUPSProxy.sol";
import {BeHYPE} from "../src/BeHYPE.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {StakingCore} from "../src/StakingCore.sol";
import {WithdrawManager} from "../src/WithdrawManager.sol";
import {StakingCore} from "../src/StakingCore.sol";
import {L1Read} from "../src/lib/L1Read.sol";
import {SpotBalanceMock} from "./mock/SpotBalanceMock.sol";
import {DelegatorSummaryMock} from "./mock/DelegatorSummaryMock.sol";
import "forge-std/console.sol";

contract BaseTest is Test {
    BeHYPE public beHYPE;
    RoleRegistry public roleRegistry;
    WithdrawManager public withdrawManager;
    StakingCore public stakingCore;

    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");
    address public protocolTreasury = makeAddr("protocolTreasury");

    address constant SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;
    address constant DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000805;

    function _getProxyImplementation(address proxy) internal view returns (address) {
        bytes32 implSlot = vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT);
        return address(uint160(uint256(implSlot)));
    }

    function setUp() public virtual {
        SpotBalanceMock spotBalanceMock = new SpotBalanceMock();
        DelegatorSummaryMock delegatorSummaryMock = new DelegatorSummaryMock();
        L1Read l1Read = new L1Read();
        
        vm.etch(SPOT_BALANCE_PRECOMPILE_ADDRESS, address(spotBalanceMock).code);
        vm.etch(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, address(delegatorSummaryMock).code);
        // TODO: add this to an address registry
        vm.etch(0xb7467E0524Afba7006957701d1F06A59000d15A2, address(l1Read).code);
        
        RoleRegistry roleRegistryImpl = new RoleRegistry();
        roleRegistry = RoleRegistry(address(new UUPSProxy(
            address(roleRegistryImpl),
            abi.encodeWithSelector(RoleRegistry.initialize.selector, admin, protocolTreasury)
        )));

        BeHYPE beHYPEImpl = new BeHYPE();
        beHYPE = BeHYPE(address(new UUPSProxy(
            address(beHYPEImpl),
            abi.encodeWithSelector(
                BeHYPE.initialize.selector,
                "BeHYPE Token",
                "BeHYPE",
                address(roleRegistry),
                address(0)
            )
        )));

        StakingCore stakingCoreImpl = new StakingCore();
        stakingCore = StakingCore(payable(address(new UUPSProxy(
            address(stakingCoreImpl),
            abi.encodeWithSelector(
                StakingCore.initialize.selector,
                address(roleRegistry),
                address(beHYPE),
                400,
                true
            )
        ))));

        WithdrawManager withdrawManagerImpl = new WithdrawManager();
        withdrawManager = WithdrawManager(payable(address(new UUPSProxy(
            address(withdrawManagerImpl),
            abi.encodeWithSelector(WithdrawManager.initialize.selector,
                0.1 ether,
                100 ether,
                100,
                30,
                address(roleRegistry), 
                address(beHYPE),
                address(stakingCore),
                5000 ether,
                1 ether
            )
        ))));

        vm.startPrank(admin);
        beHYPE.setStakingCore(address(stakingCore));
        roleRegistry.grantRole(roleRegistry.PROTOCOL_ADMIN(), admin);
        roleRegistry.grantRole(roleRegistry.PROTOCOL_GUARDIAN(), admin);
        roleRegistry.grantRole(roleRegistry.PROTOCOL_PAUSER(), admin);
        roleRegistry.grantRole(roleRegistry.PROTOCOL_UNPAUSER(), admin);
        vm.stopPrank();

        vm.deal(user, 10 ether);
    }

    function _mintTokens(address to, uint256 amount) internal {
        vm.prank(address(stakingCore));
        beHYPE.mint(to, amount);
    }

    function _burnTokens(address from, uint256 amount) internal {
        vm.prank(address(stakingCore));
        beHYPE.burn(from, amount);
    }

    function _pauseBeHYPE() internal {
        vm.prank(admin);
        console.log("Pause functionality not implemented in current BeHYPE contract");
    }

    function _unpauseBeHYPE() internal {
        vm.prank(admin);
        console.log("Unpause functionality not implemented in current BeHYPE contract");
    }

    function _setSpotBalance(address user, uint64 token, uint256 total, uint256 hold, uint256 entryNtl) internal {
        // total = total / 1e10;
        // hold = hold / 1e10;
        // entryNtl = entryNtl / 1e10;

        bytes32 userTokenKey = keccak256(abi.encode(user, token));
        bytes32 balanceSlot = keccak256(abi.encode(userTokenKey, uint256(0)));
        vm.store(SPOT_BALANCE_PRECOMPILE_ADDRESS, balanceSlot, bytes32(uint256(total)));
        
        balanceSlot = keccak256(abi.encode(userTokenKey, uint256(1)));
        vm.store(SPOT_BALANCE_PRECOMPILE_ADDRESS, balanceSlot, bytes32(uint256(hold)));
        
        balanceSlot = keccak256(abi.encode(userTokenKey, uint256(2)));
        vm.store(SPOT_BALANCE_PRECOMPILE_ADDRESS, balanceSlot, bytes32(uint256(entryNtl)));
    }

    function _setDelegatorSummary(
        address user, 
        uint256 delegated, 
        uint256 undelegated, 
        uint256 totalPendingWithdrawal, 
        uint256 nPendingWithdrawals
    ) internal {
        // delegated = delegated / 1e10;
        // undelegated = undelegated / 1e10;
        // totalPendingWithdrawal = totalPendingWithdrawal / 1e10;

        bytes32 userKey = keccak256(abi.encode(user));
        bytes32 summarySlot = keccak256(abi.encode(userKey, uint256(0))); 
        vm.store(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, summarySlot, bytes32(uint256(delegated)));
        
        summarySlot = keccak256(abi.encode(userKey, uint256(1)));
        vm.store(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, summarySlot, bytes32(uint256(undelegated)));
        
        summarySlot = keccak256(abi.encode(userKey, uint256(2)));
        vm.store(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, summarySlot, bytes32(uint256(totalPendingWithdrawal)));
        
        summarySlot = keccak256(abi.encode(userKey, uint256(3)));
        vm.store(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, summarySlot, bytes32(uint256(nPendingWithdrawals)));
    }
}

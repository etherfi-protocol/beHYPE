// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSProxy} from "../src/lib/UUPSProxy.sol";
import {BeHYPE} from "../src/BeHYPE.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {StakingCore} from "../src/StakingCore.sol";
import {WithdrawManager} from "../src/WithdrawManager.sol";
import "forge-std/console.sol";

contract BaseTest is Test {
    BeHYPE public beHYPE;
    address public stakingCore;
    RoleRegistry public roleRegistry;

    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    function _getProxyImplementation(address proxy) internal view returns (address) {
        bytes32 implSlot = vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT);
        return address(uint160(uint256(implSlot)));
    }

    function setUp() public virtual {
        stakingCore = makeAddr("stakingCore");

        // Deploy RoleRegistry
        RoleRegistry roleRegistryImpl = new RoleRegistry();
        roleRegistry = RoleRegistry(address(new UUPSProxy(
            address(roleRegistryImpl),
            abi.encodeWithSelector(RoleRegistry.initialize.selector, admin)
        )));

        BeHYPE beHYPEImpl = new BeHYPE();   

        beHYPE = BeHYPE(address(new UUPSProxy(
            address(beHYPEImpl),
            abi.encodeWithSelector(
                BeHYPE.initialize.selector,
                "BeHYPE Token",
                "BeHYPE",
                address(roleRegistry),
                stakingCore
            )
        )));

        // Deploy StakingCore
        StakingCore stakingCoreImpl = new StakingCore();
        stakingCore = StakingCore(address(new UUPSProxy(
            address(stakingCoreImpl),
            abi.encodeWithSelector(StakingCore.initialize.selector, address(roleRegistry), address(beHYPE))
        )));

        // Deploy WithdrawManager
        WithdrawManager withdrawManagerImpl = new WithdrawManager();
        withdrawManager = WithdrawManager(address(new UUPSProxy(
            address(withdrawManagerImpl),
            abi.encodeWithSelector(WithdrawManager.initialize.selector, address(roleRegistry), address(beHYPE))
        )));

    }

    function _mintTokens(address to, uint256 amount) internal {
        vm.prank(stakingCore);
        beHYPE.mint(to, amount);
    }

    function _burnTokens(address from, uint256 amount) internal {
        vm.prank(stakingCore);
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
}

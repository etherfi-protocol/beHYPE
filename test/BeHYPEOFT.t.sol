// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {UUPSProxy} from "../src/lib/UUPSProxy.sol";
import {BeHYPEOFT} from "../src/BeHYPEOFT.sol";
import {SendParam, MessagingFee} from "lib/devtools/packages/oft-evm/contracts/interfaces/IOFT.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {Origin} from "lib/devtools/packages/oapp-evm/contracts/oapp/OAppReceiver.sol";
import {LayerZeroEndpointMock} from "./mock/LayerZeroEndpointMock.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract BeHYPEOFTTest is Test {
    
    BeHYPEOFT public beHYPEOFT;
    LayerZeroEndpointMock public lzEndpoint;
    
    address public guardian = makeAddr("guardian");
    address public pauser = makeAddr("pauser");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");
    
    function setUp() public {
        lzEndpoint = new LayerZeroEndpointMock();
        
        BeHYPEOFT beHYPEOFTImpl = new BeHYPEOFT(address(lzEndpoint));
        beHYPEOFT = BeHYPEOFT(address(new UUPSProxy(
            address(beHYPEOFTImpl),
            abi.encodeWithSelector(BeHYPEOFT.initialize.selector, "BeHYPE Token", "BeHYPE", guardian)
        )));
        
        vm.deal(user, 10 ether);
        vm.deal(user2, 10 ether);
    }

    function test_Configuration() public {
        assertEq(beHYPEOFT.name(), "BeHYPE Token");
        assertEq(beHYPEOFT.symbol(), "BeHYPE");
        assertEq(address(beHYPEOFT.endpoint()), address(lzEndpoint));
        assertEq(beHYPEOFT.owner(), guardian);
        assertEq(beHYPEOFT.decimals(), 18);
    }

    function test_Ownership() public {
        assertEq(beHYPEOFT.owner(), guardian);
        
        // Test that guardian can set roles
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        assertTrue(beHYPEOFT.hasRole(pauser, beHYPEOFT.PROTOCOL_PAUSER()));
    }

    function test_RoleManagement() public {
        address[] memory initialPausers = beHYPEOFT.roleHolders(beHYPEOFT.PROTOCOL_PAUSER());
        address[] memory initialUnpausers = beHYPEOFT.roleHolders(beHYPEOFT.PROTOCOL_UNPAUSER());
        
        assertEq(initialPausers.length, 0);
        assertEq(initialUnpausers.length, 0);
        
        assertFalse(beHYPEOFT.hasRole(pauser, beHYPEOFT.PROTOCOL_PAUSER()));
        assertFalse(beHYPEOFT.hasRole(guardian, beHYPEOFT.PROTOCOL_UNPAUSER()));

        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(guardian, beHYPEOFT.PROTOCOL_UNPAUSER(), true);
        vm.stopPrank();

        assertTrue(beHYPEOFT.hasRole(pauser, beHYPEOFT.PROTOCOL_PAUSER()));
        assertTrue(beHYPEOFT.hasRole(guardian, beHYPEOFT.PROTOCOL_UNPAUSER()));

        address[] memory pausers = beHYPEOFT.roleHolders(beHYPEOFT.PROTOCOL_PAUSER());
        address[] memory unpausers = beHYPEOFT.roleHolders(beHYPEOFT.PROTOCOL_UNPAUSER());
        
        assertEq(pausers.length, 1);
        assertEq(unpausers.length, 1);
        assertEq(pausers[0], pauser);
        assertEq(unpausers[0], guardian);
    }

    function test_RoleManagement_OnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(BeHYPEOFT.OnlyOwner.selector));
        beHYPEOFT.setRole(pauser, 1, true);
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, 1, true);
        vm.stopPrank();
        assertTrue(beHYPEOFT.hasRole(pauser, 1));
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(user, 1, true);
        vm.stopPrank();
        assertTrue(beHYPEOFT.hasRole(user, 1));
    }

    function test_PauseBridge_WithoutRole() public {
        assertFalse(beHYPEOFT.paused());
        
        vm.expectRevert(abi.encodeWithSelector(BeHYPEOFT.NotAuthorized.selector));
        beHYPEOFT.pauseBridge();
        
        assertFalse(beHYPEOFT.paused());
    }

    function test_PauseBridge_WithRole() public {
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        assertFalse(beHYPEOFT.paused());
        
        vm.prank(pauser);
        beHYPEOFT.pauseBridge();
        
        assertTrue(beHYPEOFT.paused());
    }

    function test_UnpauseBridge_WithoutRole() public {
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        vm.prank(pauser);
        beHYPEOFT.pauseBridge();
        assertTrue(beHYPEOFT.paused());
        
        vm.expectRevert(abi.encodeWithSelector(BeHYPEOFT.NotAuthorized.selector));
        beHYPEOFT.unpauseBridge();
        
        assertTrue(beHYPEOFT.paused());
    }

    function test_UnpauseBridge_WithRole() public {
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(guardian, beHYPEOFT.PROTOCOL_UNPAUSER(), true);
        vm.stopPrank();
        
        vm.prank(pauser);
        beHYPEOFT.pauseBridge();
        assertTrue(beHYPEOFT.paused());
        
        vm.prank(guardian);
        beHYPEOFT.unpauseBridge();
        
        assertFalse(beHYPEOFT.paused());
    }

    function test_OFT_Send_WhenPaused() public {
        vm.prank(guardian);
        beHYPEOFT.setPeer(30103, bytes32(uint256(uint160(address(0x1234)))));
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        // First simulate receiving tokens from another chain
        vm.prank(address(lzEndpoint));
        beHYPEOFT.lzReceive(
            Origin({
                srcEid: 30103,
                sender: bytes32(uint256(uint160(address(0x1234)))),
                nonce: 1
            }),
            keccak256("test-guid"),
            abi.encodePacked(
                bytes32(uint256(uint160(user))),
                uint64(1000000000), // 1000 ether in OFT format
                bytes("")
            ),
            address(0),
            ""
        );
        
        vm.startPrank(user);
        beHYPEOFT.approve(address(beHYPEOFT), 1000 ether);
        
        SendParam memory sendParam = SendParam({
            dstEid: 30103,
            to: bytes32(uint256(uint160(user2))),
            amountLD: 100 ether,
            minAmountLD: 99 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        MessagingFee memory fee = MessagingFee({
            nativeFee: 0.01 ether,
            lzTokenFee: 0
        });
        
        beHYPEOFT.send{value: 0.01 ether}(sendParam, fee, user);
        vm.stopPrank();
        
        vm.prank(pauser);
        beHYPEOFT.pauseBridge();
        
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)); 
        beHYPEOFT.send{value: 0.01 ether}(sendParam, fee, user);
        vm.stopPrank();
    }

    function test_OFT_Send_WhenUnpaused() public {
        vm.prank(guardian);
        beHYPEOFT.setPeer(30103, bytes32(uint256(uint160(address(0x1234)))));
        
        // First simulate receiving tokens from another chain
        vm.prank(address(lzEndpoint));
        beHYPEOFT.lzReceive(
            Origin({
                srcEid: 30103,
                sender: bytes32(uint256(uint160(address(0x1234)))),
                nonce: 1
            }),
            keccak256("test-guid"),
            abi.encodePacked(
                bytes32(uint256(uint160(user))),
                uint64(1000000000), // 1000 ether in OFT format
                bytes("")
            ),
            address(0),
            ""
        );
        
        // Now user has tokens and can send them
        vm.startPrank(user);
        beHYPEOFT.approve(address(beHYPEOFT), 1000 ether);
        
        SendParam memory sendParam = SendParam({
            dstEid: 30103,
            to: bytes32(uint256(uint160(user2))),
            amountLD: 100 ether,
            minAmountLD: 99 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        MessagingFee memory fee = MessagingFee({
            nativeFee: 0.01 ether,
            lzTokenFee: 0
        });
        
        beHYPEOFT.send{value: 0.01 ether}(sendParam, fee, user);
        
        // In OFT, tokens are burned when sent (not held in contract)
        assertEq(beHYPEOFT.balanceOf(address(beHYPEOFT)), 0);
        assertEq(beHYPEOFT.balanceOf(user), 900 ether);
        
        vm.stopPrank();
    }

    function test_OFT_Receive_WhenPaused() public {
        vm.prank(guardian);
        beHYPEOFT.setPeer(30103, bytes32(uint256(uint160(address(0x1234)))));
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        vm.prank(pauser);
        beHYPEOFT.pauseBridge();
        
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(address(lzEndpoint));
        beHYPEOFT.lzReceive(
            Origin({
                srcEid: 30103,
                sender: bytes32(uint256(uint160(address(0x1234)))),
                nonce: 1
            }),
            keccak256("test-guid"),
            abi.encodePacked(
                bytes32(uint256(uint160(user2))),
                uint64(1000000),
                bytes("")
            ),
            address(0),
            ""
        );
    }

    function test_OFT_Receive_WhenUnpaused() public {
        vm.prank(guardian);
        beHYPEOFT.setPeer(30103, bytes32(uint256(uint160(address(0x1234)))));
        
        uint256 balanceBefore = beHYPEOFT.balanceOf(user2);
        
        vm.prank(address(lzEndpoint));
        beHYPEOFT.lzReceive(
            Origin({
                srcEid: 30103,
                sender: bytes32(uint256(uint160(address(0x1234)))),
                nonce: 1
            }),
            keccak256("test-guid"),
            abi.encodePacked(
                bytes32(uint256(uint160(user2))),
                uint64(1000000),
                bytes("")
            ),
            address(0),
            ""
        );
        
        // In OFT, tokens are minted when received (not transferred from contract balance)
        assertEq(beHYPEOFT.balanceOf(user2), balanceBefore + 1 ether);
        assertEq(beHYPEOFT.balanceOf(address(beHYPEOFT)), 0);
    }

    function test_UpgradeableViaOwner() public {
        address newImplementation = address(new BeHYPEOFT(address(lzEndpoint)));
        
        vm.expectRevert(abi.encodeWithSelector(BeHYPEOFT.OnlyOwner.selector));
        beHYPEOFT.upgradeToAndCall(newImplementation, "");
        
        vm.prank(guardian);
        beHYPEOFT.upgradeToAndCall(newImplementation, "");
        
        address currentImplementation = address(uint160(uint256(vm.load(address(beHYPEOFT), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc))));
        assertEq(currentImplementation, newImplementation);
    }

    function test_RoleRevocation() public {
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        assertTrue(beHYPEOFT.hasRole(pauser, beHYPEOFT.PROTOCOL_PAUSER()));
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), false);
        vm.stopPrank();
        
        assertFalse(beHYPEOFT.hasRole(pauser, beHYPEOFT.PROTOCOL_PAUSER()));
        
        address[] memory pausers = beHYPEOFT.roleHolders(beHYPEOFT.PROTOCOL_PAUSER());
        assertEq(pausers.length, 0);
    }

    function test_MultipleRoleHolders() public {
        vm.startPrank(guardian);
        beHYPEOFT.setRole(pauser, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(user, beHYPEOFT.PROTOCOL_PAUSER(), true);
        vm.stopPrank();
        
        vm.startPrank(guardian);
        beHYPEOFT.setRole(guardian, beHYPEOFT.PROTOCOL_UNPAUSER(), true);
        vm.stopPrank();
        
        address[] memory pausers = beHYPEOFT.roleHolders(beHYPEOFT.PROTOCOL_PAUSER());
        assertEq(pausers.length, 2);
        
        vm.prank(pauser);
        beHYPEOFT.pauseBridge();
        assertTrue(beHYPEOFT.paused());
        
        vm.prank(guardian);
        beHYPEOFT.unpauseBridge();
        
        vm.prank(user);
        beHYPEOFT.pauseBridge();
        assertTrue(beHYPEOFT.paused());
    }
}

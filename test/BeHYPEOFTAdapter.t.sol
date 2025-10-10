// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest, UUPSProxy, BeHYPE, BeHYPEOFTAdapter, IRoleRegistry} from "./Base.t.sol";
import {SendParam, MessagingFee} from "lib/devtools/packages/oft-evm/contracts/interfaces/IOFT.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {Origin} from "lib/devtools/packages/oapp-evm/contracts/oapp/OAppReceiver.sol";

contract BeHYPEOFTAdapterTest is BaseTest {
    
    function setUp() public override {
        super.setUp();
    }

    function test_Configuration() public {
        assertEq(beHYPEOFTAdapter.token(), address(beHYPE));
        assertEq(address(beHYPEOFTAdapter.endpoint()), address(lzEndpoint));
        assertEq(address(beHYPEOFTAdapter.roleRegistry()), address(roleRegistry));
        assertEq(address(beHYPEOFTAdapter.owner()), guardian);
    }
    
    function test_UpgradeableViaAccessControl() public {
        BeHYPE beHYPEImpl2 = new BeHYPE();
        address beHYPE2 = address(new UUPSProxy(
            address(beHYPEImpl2),
            abi.encodeWithSelector(
                BeHYPE.initialize.selector,
                "BeHYPE Token 2",
                "BeHYPE 2",
                address(roleRegistry),
                address(0)
            )
        ));
        
        address newImplementation = address(new BeHYPEOFTAdapter(beHYPE2, address(lzEndpoint)));
        
        vm.expectRevert(abi.encodeWithSelector(IRoleRegistry.OnlyProtocolUpgrader.selector));
        beHYPEOFTAdapter.upgradeToAndCall(newImplementation, "");
        
        vm.prank(admin);
        beHYPEOFTAdapter.upgradeToAndCall(newImplementation, "");

        assertEq(beHYPEOFTAdapter.token(), beHYPE2);
    }

    function test_PauseBridge() public {
        assertFalse(beHYPEOFTAdapter.paused());
        
        vm.expectRevert(abi.encodeWithSelector(BeHYPEOFTAdapter.NotAuthorized.selector));
        beHYPEOFTAdapter.pauseBridge();
        
        vm.prank(pauser);
        beHYPEOFTAdapter.pauseBridge();
        
        assertTrue(beHYPEOFTAdapter.paused());
    }

    function test_UnpauseBridge() public {
        vm.prank(pauser);
        beHYPEOFTAdapter.pauseBridge();
        assertTrue(beHYPEOFTAdapter.paused());
        
        vm.prank(guardian);
        beHYPEOFTAdapter.unpauseBridge();
        
        assertFalse(beHYPEOFTAdapter.paused());
    }

    function test_OFT_Send_WhenPaused() public {
        vm.prank(guardian);
        beHYPEOFTAdapter.setPeer(30103, bytes32(uint256(uint160(address(0x1234)))));
        
        _mintTokens(user, 1000 ether);
        vm.startPrank(user);
        beHYPE.approve(address(beHYPEOFTAdapter), 1000 ether);
        
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
        
        beHYPEOFTAdapter.send{value: 0.01 ether}(sendParam, fee, user);
        vm.stopPrank();
        
        vm.prank(pauser);
        beHYPEOFTAdapter.pauseBridge();
        
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)); 
        beHYPEOFTAdapter.send{value: 0.01 ether}(sendParam, fee, user);
        vm.stopPrank();
    }

    function test_OFT_Send_WhenUnpaused() public {
        vm.prank(guardian);
        beHYPEOFTAdapter.setPeer(30103, bytes32(uint256(uint160(address(0x1234)))));
        
        _mintTokens(user, 1000 ether);
        vm.startPrank(user);
        beHYPE.approve(address(beHYPEOFTAdapter), 1000 ether);
        
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
        
        beHYPEOFTAdapter.send{value: 0.01 ether}(sendParam, fee, user);
        
        assertEq(beHYPE.balanceOf(address(beHYPEOFTAdapter)), 100 ether);
        assertEq(beHYPE.balanceOf(user), 900 ether);
        
        vm.stopPrank();
    }

    function test_OFT_Receive_WhenPaused() public {
        vm.prank(guardian);
        beHYPEOFTAdapter.setPeer(30103, bytes32(uint256(uint160(address(0x1234)))));
        
        _mintTokens(address(beHYPEOFTAdapter), 1000000 ether);
        
        vm.prank(pauser);
        beHYPEOFTAdapter.pauseBridge();
        
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(address(lzEndpoint));
        beHYPEOFTAdapter.lzReceive(
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
        beHYPEOFTAdapter.setPeer(30103, bytes32(uint256(uint160(address(0x1234)))));
        
        _mintTokens(address(beHYPEOFTAdapter), 1000000 ether);
        
        uint256 balanceBefore = beHYPE.balanceOf(user2);
        
        vm.prank(address(lzEndpoint));
        beHYPEOFTAdapter.lzReceive(
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
        
        assertEq(beHYPE.balanceOf(user2), balanceBefore + 1 ether);
        assertEq(beHYPE.balanceOf(address(beHYPEOFTAdapter)), 999999 ether);
    }
}

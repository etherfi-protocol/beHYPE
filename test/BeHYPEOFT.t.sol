// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest, UUPSProxy, BeHYPE, BeHYPEOFTAdapter} from "./Base.t.sol";
import {BeHYPEOFT} from "../src/BeHYPEOFT.sol";

contract BeHYPEOFTTest is BaseTest {
    BeHYPEOFT public beHYPEOFT;
    
    function setUp() public override {
        super.setUp();
        
        BeHYPEOFT beHYPEOFTImpl = new BeHYPEOFT(address(lzEndpoint));
        beHYPEOFT = BeHYPEOFT(address(new UUPSProxy(
            address(beHYPEOFTImpl),
            abi.encodeWithSelector(
                BeHYPEOFT.initialize.selector,
                "BeHYPE OFT",
                "BeHYPE-OFT",
                admin
            )
        )));
    }

    function test_Configuration() public {
        assertEq(beHYPEOFT.name(), "BeHYPE OFT");
        assertEq(beHYPEOFT.symbol(), "BeHYPE-OFT");
        assertEq(beHYPEOFT.owner(), admin);
        assertEq(address(beHYPEOFT.endpoint()), address(lzEndpoint));
    }
    
    function test_UpgradeableViaAccessControl() public {
        address newImplementation = address(new BeHYPEOFT(address(lzEndpoint)));
        
        vm.expectRevert();
        beHYPEOFT.upgradeToAndCall(newImplementation, "");
        
        vm.prank(admin);
        beHYPEOFT.upgradeToAndCall(newImplementation, "");
    }
}

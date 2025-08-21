// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract StakingCoreTest is BaseTest {

    function setUp() public override {
        super.setUp();
    }

    function test_stake() public {
        vm.prank(user);
        stakingCore.stake{value: 1 ether}("test");

        assertEq(beHYPE.balanceOf(user), 1 ether);

        vm.prank(admin);
        vm.warp(block.timestamp + 1 days);
        stakingCore.updateExchangeRatio();

        assertEq(stakingCore.exchangeRatio(), 1 ether);
    }

    function test_ExchangeRatio() public {
        test_stake();
        DelegatorSummaryMock(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS).setDelegatorSummary(address(stakingCore), 0.01 ether, 0, 0, 0);
        vm.warp(block.timestamp + 365 days);

        vm.prank(admin);
        stakingCore.updateExchangeRatio();

        vm.warp(block.timestamp + 1);

    }

}

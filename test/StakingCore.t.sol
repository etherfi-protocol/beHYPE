// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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
        vm.roll(block.number + 5);
        stakingCore.updateExchangeRatio();

        assertEq(stakingCore.exchangeRatio(), 1 ether);
    }

    function test_ExchangeRatio() public {
        test_stake();

        // 1% APR
        DelegatorSummaryMock(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS).setDelegatorSummary(address(stakingCore), 0.01 ether, 0, 0);
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 5);

        vm.prank(admin);
        stakingCore.updateExchangeRatio();

        assertEq(stakingCore.exchangeRatio(), 1.01 ether);
        assertEq(stakingCore.BeHYPEToHYPE(1 ether), 1.01 ether);
        assertEq(stakingCore.HYPEToBeHYPE(1 ether), 990099009900990099);

    }

    function test_ExchangeRatio_should_revert_if_apr_exceeds_threshold() public {
        test_stake();

        // 5% APR
        DelegatorSummaryMock(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS).setDelegatorSummary(address(stakingCore), 0.05 ether, 0, 0);
        vm.warp(block.timestamp + 365 days);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakingCore.ExchangeRatioChangeExceedsThreshold.selector, 500));
        stakingCore.updateExchangeRatio();
    }

    function test_ExchangeRatio_negative() public {
        test_ExchangeRatio();

        // -1% APR
        DelegatorSummaryMock(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS).setDelegatorSummary(address(stakingCore), 0, 0, 0);
        vm.warp(block.timestamp + 365 days);

        vm.prank(admin);
        stakingCore.updateExchangeRatio();
        assertEq(stakingCore.exchangeRatio(), 1 ether);
        assertEq(stakingCore.BeHYPEToHYPE(1 ether), 1 ether);
        assertEq(stakingCore.HYPEToBeHYPE(1 ether), 1 ether);
    }

    function test_ExchangeRatio_should_revert_if_apr_exceeds_threshold_negative() public {
        test_ExchangeRatio();

        // -10% APR (-0.01 in 1/10 year ~ -10% in apr)
        DelegatorSummaryMock(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS).setDelegatorSummary(address(stakingCore), 0, 0, 0);
        vm.warp(block.timestamp + 36.5 days);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakingCore.ExchangeRatioChangeExceedsThreshold.selector, 990));
        stakingCore.updateExchangeRatio();
    }

    function test_MockDepositToHyperCore() public {
        test_stake();

        uint256 balanceBefore = address(stakingCore).balance;
        uint256 totalPooledEtherBefore = stakingCore.getTotalProtocolHype();

        mockDepositToHyperCore(1 ether);

        assertEq(address(stakingCore).balance, balanceBefore - 1 ether);
        assertEq(stakingCore.getTotalProtocolHype(), totalPooledEtherBefore);
    }

    function test_RevertUpgradeUnauthorized() public {
        StakingCore newStakingCoreImpl = new StakingCore();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IRoleRegistry.OnlyProtocolUpgrader.selector));
        stakingCore.upgradeToAndCall(address(newStakingCoreImpl), "");
    }

    function test_UpgradeSuccess() public {
        StakingCore newStakingCoreImpl = new StakingCore();

        vm.prank(admin);
        stakingCore.upgradeToAndCall(address(newStakingCoreImpl), "");

        assertEq(stakingCore.exchangeRatio(), 1 ether);
    }

    function test_RevertReinitialization() public {
        vm.prank(admin);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        stakingCore.initialize(
            address(roleRegistry),
            address(beHYPE),
            address(withdrawManager),
            400,
            true
        );
    }
    
    function test_depositToHyperCore_should_revert_with_various_precision_loss_scenarios() public {
        test_stake();
        
        uint256[] memory problematicAmounts = new uint256[](3);
        problematicAmounts[0] = 1 ether + 1;
        problematicAmounts[1] = 1 ether + 1000;
        problematicAmounts[2] = 1 ether + 1e9;

        for (uint256 i = 0; i < problematicAmounts.length; i++) {
            uint256 amount = problematicAmounts[i];
            uint256 expectedTruncated = amount / 1e10 * 1e10;
            
            vm.prank(admin);
            vm.expectRevert(abi.encodeWithSelector(
                IStakingCore.PrecisionLossDetected.selector, 
                amount, 
                expectedTruncated
            ));
            stakingCore.depositToHyperCore(amount);
        }
    }

    function test_ExchangeRatioUpdateGuard() public {
        test_stake();
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user);
        beHYPE.approve(address(withdrawManager), 1 ether);
        withdrawManager.withdraw(1 ether, false);
        vm.stopPrank();

        vm.startPrank(admin);
        stakingCore.depositToHyperCore(0.000001 ether);

        vm.expectRevert(abi.encodeWithSelector(IStakingCore.ExchangeRatioUpdateTooSoon.selector, 5, 0));
        stakingCore.updateExchangeRatio();

        stakingCore.withdrawFromHyperCore(0.000001 ether);

        vm.roll(block.number + 4);
        vm.expectRevert(abi.encodeWithSelector(IStakingCore.ExchangeRatioUpdateTooSoon.selector, 5, 4));
        stakingCore.updateExchangeRatio();

        vm.roll(block.number + 5);
        stakingCore.updateExchangeRatio();
    }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {L2BeHYPEOAppStaker} from "../../src/L2BeHYPEOAppStaker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

///
/// Simple script to stake from L2BeHYPEOAppStaker
/// 
/// Usage:
///   forge script script/oapp/TestStake.s.sol:TestStake \
///     --rpc-url $RPC \
///     --broadcast \
///     -vvvv
contract TestStake is Script {
    address payable public constant SCROLL_DEPLOYMENT = payable(address(0xd713399553215AdE231175fCB44857e66487F54E));
    address public constant WHYPE = address(0xd83E3d560bA6F05094d9D8B3EB8aaEA571D1864E);
    
    // Small hardcoded values
    uint256 public constant STAKE_AMOUNT = 0.00047832878733 ether; 
    
    function run() external {
        address receiver = msg.sender; // Receiver is the caller
        
        vm.startBroadcast();
        
        L2BeHYPEOAppStaker staker = L2BeHYPEOAppStaker(SCROLL_DEPLOYMENT);
        IERC20 whype = IERC20(WHYPE);
        
        // Approve WHYPE tokens
        whype.approve(address(staker), STAKE_AMOUNT);
        
        // Quote the fee needed
        uint256 fee = staker.quoteStake(STAKE_AMOUNT, receiver);
        console.log("Required fee:", fee);
            
        // Stake with the quoted fee (adding small buffer)
        staker.stake{value: fee + 0.001 ether}(STAKE_AMOUNT, 0xfdD2c5eb4A309Fd65DBeB476dC618e91f611d779);
        
        console.log("Staked %s WHYPE tokens", STAKE_AMOUNT);
        
        vm.stopBroadcast();
    }
}

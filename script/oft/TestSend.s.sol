// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "forge-std/StdJson.sol";
import {IOFT, SendParam} from "lib/devtools/packages/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee} from "lib/devtools/packages/oapp-evm/contracts/oapp/OAppSender.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract TestSend is Script {
    using stdJson for string;

    /*
    * For Scroll → HyperEVM:
    * forge script script/OFT/TestSend.s.sol:TestSend \
    * --rpc-url $SCROLL_RPC \
    * --private-key $PRIVATE_KEY \
    * --broadcast
    *
    * For HyperEVM → Scroll:
    * forge script script/OFT/TestSend.s.sol:TestSend \
    * --rpc-url $HYPEREVM_RPC \
    * --private-key $PRIVATE_KEY \
    * --broadcast
    */
    function run() external {
        string memory config = vm.readFile("config/production.json");
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        
        uint256 chainId = block.chainid;
        bool isScroll = (chainId == 534352);
        
        address oftAddress;
        uint32 dstEid;
        
        if (isScroll) {
            oftAddress = config.readAddress(".addresses.BeHYPEOFT");
            dstEid = uint32(config.readUint(".layerZero.hyperEVM.eid"));
        } else {
            oftAddress = config.readAddress(".addresses.BeHYPEOFTAdapter");
            dstEid = uint32(config.readUint(".layerZero.scroll.eid"));
        }
        
        vm.startBroadcast(privateKey);
        
        IOFT oft = IOFT(oftAddress);
        uint256 amountToSend = 0.01 ether;
        
        SendParam memory param = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(sender))),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        MessagingFee memory fee = oft.quoteSend(param, false);
        
        if (!isScroll) {
            address beHYPE = config.readAddress(".addresses.BeHYPE");
            IERC20(beHYPE).approve(oftAddress, amountToSend);
        }
        
        oft.send{value: fee.nativeFee}(param, fee, sender);
        

        
        vm.stopBroadcast();
    }
}


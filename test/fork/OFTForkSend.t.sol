// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "forge-std/StdJson.sol";
import {IOFT, SendParam} from "lib/devtools/packages/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee} from "lib/devtools/packages/oapp-evm/contracts/oapp/OAppSender.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../script/utils/GnosisHelpers.sol";

contract OFTForkSend is Test, GnosisHelpers {
    using stdJson for string;

    string config;

    address adapter;
    address optimismOFT;
    address beHYPE;
    uint32 optimismEid;
    uint32 hyperEVMEid;

    address user = address(0xBEEF);
    uint256 sendAmount = 0.01 ether;

    function setUp() public {
        config = vm.readFile("config/production.json");
        adapter = config.readAddress(".addresses.BeHYPEOFTAdapter");
        optimismOFT = config.readAddress(".addresses.BeHYPEOFT");
        beHYPE = config.readAddress(".addresses.BeHYPE");
        optimismEid = uint32(config.readUint(".layerZero.optimism.eid"));
        hyperEVMEid = uint32(config.readUint(".layerZero.hyperEVM.eid"));
    }

    function testSendFromHyperEVMToOptimism() public {
        vm.createSelectFork(vm.envString("HYPEREVM_RPC"));

        executeGnosisTransactionBundle("output/hyperevm-adapter-config-bundle.json");

        deal(beHYPE, user, sendAmount);
        deal(user, 1 ether);

        vm.startPrank(user);

        IERC20(beHYPE).approve(adapter, sendAmount);

        SendParam memory param = SendParam({
            dstEid: optimismEid,
            to: bytes32(uint256(uint160(user))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = IOFT(adapter).quoteSend(param, false);
        console.log("HyperEVM -> OP native fee:", fee.nativeFee);

        IOFT(adapter).send{value: fee.nativeFee}(param, fee, user);

        vm.stopPrank();
    }

    function testSendFromOptimismToHyperEVM() public {
        vm.createSelectFork(vm.envString("OPTIMISM_RPC"));

        deal(optimismOFT, user, sendAmount);
        deal(user, 1 ether);

        vm.startPrank(user);

        SendParam memory param = SendParam({
            dstEid: hyperEVMEid,
            to: bytes32(uint256(uint160(user))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = IOFT(optimismOFT).quoteSend(param, false);
        console.log("OP -> HyperEVM native fee:", fee.nativeFee);

        IOFT(optimismOFT).send{value: fee.nativeFee}(param, fee, user);

        vm.stopPrank();
    }
}

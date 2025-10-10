// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "forge-std/StdJson.sol";
import "../../src/BeHYPEOFT.sol";
import "../../src/BeHYPEOFTAdapter.sol";

/*
* For Scroll (BeHYPEOFT):
* forge script script/OFT/TransferOFTOwnership.s.sol:TransferOFTOwnership \
* --rpc-url $SCROLL_RPC \
* --broadcast
*
* For HyperEVM (BeHYPEOFTAdapter):
* forge script script/OFT/TransferOFTOwnership.s.sol:TransferOFTOwnership \
* --rpc-url $HYPEREVM_RPC \
* --broadcast
*/
contract TransferOFTOwnership is Script {
    using stdJson for string;

    string public config;
    address public scriptDeployer;
    bool public isScroll;

    function run() external {
        config = vm.readFile("config/production.json");
        scriptDeployer = msg.sender;

        vm.startBroadcast();
        
        uint256 chainId = block.chainid;
        isScroll = (chainId == 534352);

        if (isScroll) {
            _transferScrollOFTOwnership();
        } else {
            _transferHyperEVMOFTAdapterOwnership();
        }

        vm.stopBroadcast();
    }

    function _transferScrollOFTOwnership() private {
        address oftAddress = config.readAddress(".addresses.BeHYPEOFT");
        address scrollController = config.readAddress(".roles.scrollController");
        address pauser = config.readAddress(".roles.pauser");

        BeHYPEOFT oft = BeHYPEOFT(oftAddress);

        oft.setDelegate(scrollController);

        oft.setRole(pauser, oft.PROTOCOL_PAUSER(), true);

        oft.setRole(scrollController, oft.PROTOCOL_UNPAUSER(), true);

        oft.transferOwnership(scrollController);

    }

    function _transferHyperEVMOFTAdapterOwnership() private {
        address adapterAddress = config.readAddress(".addresses.BeHYPEOFTAdapter");
        address guardian = config.readAddress(".roles.guardian");

        BeHYPEOFTAdapter adapter = BeHYPEOFTAdapter(adapterAddress);

        adapter.setDelegate(guardian);

        adapter.transferOwnership(guardian);

        console.log("New Owner:", adapter.owner());
    }
}


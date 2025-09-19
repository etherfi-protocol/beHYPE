// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OFTUpgradeable} from "lib/devtools/packages/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @notice OFT is an ERC-20 token that extends the OFTCore contract.
contract BeHYPEOFT is OFTUpgradeable, UUPSUpgradeable {

    error OnlyOwner();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _owner
    ) public initializer {
        __Ownable_init(_owner);
        __OFT_init(_name, _symbol, _owner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        if (msg.sender != owner()) revert OnlyOwner();
    }
}

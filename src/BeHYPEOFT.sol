// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OFTUpgradeable} from "lib/devtools/packages/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableRoles} from "lib/solady/src/auth/EnumerableRoles.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

/// @notice OFT is an ERC-20 token that extends the OFTCore contract.
contract BeHYPEOFT is OFTUpgradeable, UUPSUpgradeable, EnumerableRoles, PausableUpgradeable {

    error OnlyOwner();
    error NotAuthorized();
    
    uint256 public constant PROTOCOL_PAUSER = 1;
    uint256 public constant PROTOCOL_UNPAUSER = 2;

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
        __Pausable_init();
    }

    function setRole(address holder, uint256 role, bool active) public payable override {
        if (msg.sender != owner()) revert OnlyOwner();
        super._setRole(holder, role, active);
    }

    function pauseBridge() external {
        if (!hasRole(msg.sender, PROTOCOL_PAUSER)) revert NotAuthorized();
        _pause();
    }

    function unpauseBridge() external {
        if (!hasRole(msg.sender, PROTOCOL_UNPAUSER)) revert NotAuthorized();
        _unpause();
    }

    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override whenNotPaused() returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused() returns (uint256 amountReceivedLD) {
        return super._credit(_to, _amountLD, _srcEid);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        if (msg.sender != owner()) revert OnlyOwner();
    }

}

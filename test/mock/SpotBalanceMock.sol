// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SpotBalanceMock {
    struct SpotBalance {
        uint64 total;
        uint64 hold;
        uint64 entryNtl;
    }

    mapping(address => mapping(uint64 => SpotBalance)) public spotBalances;

    constructor() {
        spotBalances[0x1234567890123456789012345678901234567890][0] = SpotBalance({
            total: 100_000_000,
            hold: 50_000_000,
            entryNtl: 10_000_000
        });
    }

    function setSpotBalance(address user, uint64 token, uint64 total, uint64 hold, uint64 entryNtl) external {
        spotBalances[user][token] = SpotBalance({
            total: total,
            hold: hold,
            entryNtl: entryNtl
        });
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        (address user, uint64 token) = abi.decode(data, (address, uint64));
        
        SpotBalance memory balance = spotBalances[user][token];
        
        return abi.encode(balance);
    }
}

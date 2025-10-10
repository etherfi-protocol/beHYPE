# Smart Contract Architecture

## Core Components

### beHYPE Token

The beHYPE token is an ERC-20 token representing staked HYPE:

- Standard ERC-20 functions with permit functionality
- Minting and burning functionality when users stake and withdraw HYPE

### WithdrawManager

The WithdrawManager manages instant and standard withdrawals (3 to 7 days) requests

- Manages withdrawal requests based on finalization determined by the oracle
- Standard withdrawal flow:
  1. beHYPE tokens are transferred to the withdrawal manager and a withdrawal request is issued. 
  Exchange rate at time of request determine the HYPE withdrawal amount.
  2. Off-chain service finalizes withdraws. beHYPE tokens are burnt and HYPE can be claimed by the users.
- Allows for instant withdrawals for a fee
- Availability for instant withdrawals is determined by a minimum liquidity threshold as a percentage of TVL and a rate limiter

### StakingCore

Core staking contract 

- Provides the exchange rate between beHYPE and HYPE by calculating the total protocol balance:
  (StakingCore contract balance) + (StakingCore L1 stake account balance) + (StakingCore L1 spot balance)
- Admin functions leveraging CoreWriter for staking, unstaking, and rebalancing on the hyperCore

## Access Control System

### RoleRegistry

- Manages all roles for the beHYPE protocol
- `PauseProtocol` function for emergency pause of staking and withdrawals

### BeHYPETimelock

Timelock with 3 day delay controlling all contract updates and 

## Cross Chain

- `BeHYPEOFTAdapter` deployed to hyperEVM 
- `BeHYPEOFT` deployed to scroll for ether.fi cash integration

## Contract Deployed Addresses

| Contract | Mainnet Address |
|----------|-----------------|
| beHYPE | 0xd8FC8F0b03eBA61F64D08B0bef69d80916E5DdA9 |
| WithdrawManager | 0x9d0B0877b9f2204CF414Ca7862E4f03506822538 |
| StakingCore | 0xCeaD893b162D38e714D82d06a7fe0b0dc3c38E0b |
| RoleRegistry | 0x90102473a816A01A9fB0809F2289438B2e294F76 |
| BeHYPETimelock | 0xA24aF73EaDD17997EeEdbEd36672e996544D2DE4 |
| BeHYPEOFTAdapter | 0x637De4A55cdD37700F9B54451B709b01040D48dF |
| BeHYPEOFT | 0xA519AfBc91986c0e7501d7e34968FEE51CD901aC | 

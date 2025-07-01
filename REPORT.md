# Decentralized VPN Bandwidth Sharing Protocol (DePIN Concept)

This document describes the design, smart contract implementation and testing of a decentralized VPN bandwidth marketplace. The protocol allows bandwidth providers and VPN users to interact directly via Ethereum smart contracts with automated payments and staking incentives.

## Protocol Design

1. **Provider registration** – Nodes stake tokens and advertise a price per MB. Staking prevents Sybil attacks and aligns incentives.
2. **User deposit** – A user chooses a provider and locks a deposit in the contract as the maximum payable amount.
3. **Session** – The user connects to the provider's VPN service off-chain. Data traffic is exchanged peer to peer; the blockchain only handles payments.
4. **Payment options** –
   - *Direct settlement*: the user ends a session by submitting the consumed bandwidth. The contract transfers the corresponding amount to the provider and refunds the rest.
   - *Voucher micropayments*: the user periodically signs a voucher reflecting total spending. The provider redeems these signed messages on-chain to claim incremental payments.
5. **Session end** – When finished, the user closes the session. Any remaining deposit is refunded. If a user disappears, the provider can force-end the session after a timeout and keep the leftover deposit.
6. **Provider exit** – A provider can deregister and withdraw the stake once there are no active sessions.

## Smart Contracts

The Solidity contract `BandwidthMarketplace.sol` implements the above logic using an ERC‑20 token for staking and payments. Key functions include:

- `registerProvider` – stake and set price
- `deregisterProvider` – withdraw stake when no sessions remain
- `startSession` – create a session with a deposit
- `endSession` – pay using direct settlement
- `redeemVoucher` – provider redeems a signed voucher
- `withdrawLeftover` – user retrieves unspent deposit
- `forceEndSession` – provider claims remaining deposit after timeout

The contract ensures correct state updates before transferring tokens to mitigate reentrancy and tracks cumulative payments to prevent voucher reuse.

## Testing

`BandwidthMarketplaceTest.sol` contains unit tests written with Foundry. The tests cover provider registration, session lifecycle, voucher redemption (including failure cases) and the forced session end mechanism. All tests pass, demonstrating the correctness of the implementation.

## Deployment

The contract can be deployed to any EVM-compatible network such as the Sepolia testnet. During deployment the ERC‑20 token address is provided to the constructor. Front-end clients can then interact with the contract to register providers and start sessions.


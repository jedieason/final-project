# Decentralized VPN Bandwidth Sharing Protocol

This repository contains the reference implementation of a decentralized VPN (dVPN) bandwidth marketplace. The project demonstrates how providers can share unused bandwidth and receive on-chain payments from users without relying on a central VPN service.

## Contents

- `contracts/` – Solidity smart contracts implementing the bandwidth marketplace
- `test/` – Foundry unit tests
- `index.html` – simple landing page
- `foundry.toml` – basic configuration for Foundry

## Overview

Providers stake tokens and register their bandwidth price. Users lock a deposit and start a VPN session with a chosen provider. Payment can either be made directly when ending a session or incrementally via signed vouchers. A provider may force-end a session if the user disappears, collecting the remaining deposit as compensation.

The contract `BandwidthMarketplace.sol` implements this logic using an ERC‑20 token for payments. `BandwidthMarketplaceTest.sol` contains unit tests covering the main scenarios such as registration, session lifecycle, voucher redemption and timeout logic.

## Running Tests

The tests require [Foundry](https://github.com/foundry-rs/foundry). After installing Foundry, run:

```bash
forge test
```

## License

MIT

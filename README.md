# JBX V2 - Vault Proof-of-concept

| Contract                   | Implementation | Description                                                                                              |
|----------------------------|----------------|----------------------------------------------------------------------------------------------------------|
| AJSingleVaultTerminalETH   | ✅              | Implements `AJSingleVaultTerminal` with support for ETH by wrapping it into wETH*.                       |
| AJSingleVaultTerminalERC20 | ✅              | Implements `AJSingleVaultTerminal` with support for ERC20 tokens.                                        |
| AJSingleVaultTerminal      | 🚫             | Implements the `AJPayoutRedemptionTerminal` and contains the abstract logic for managing a single vault. |
| AJPayoutRedemptionTerminal | 🚫             | Adds hooks for AJ where needed, allowing for an abstraction between the AJ and JBX contracts.            |
_&ast; This is needed because the EIP4626 standard only offers support for ERC20 assets_

## Risks & Assumptions

- A user trusts a vault to not lie or act in a malicious way towards them
  - Vault does not lie about ROI
  - Vault assets are withdrawable
- A malicious user may add a malicious vault to (attempt to) steal assets from other users
  - Malicious vault may return a higher 'assets' amount when redeeming than is actually being redeemed to try and trick the terminal (we have to make sure returned amounts are correct)
  - Malicious vault may try and reenter into another projects `_withdraw ` to try and fake their withdrawn amount by increasing the terminal balance (we can't allow reentry on deposit/withdraw/redeem methods)

## Setup
To set up Foundry:

1. Install [Foundry](https://github.com/gakonst/foundry).
2. Install external libraries

```bash
git submodule update --init
```

4. Run tests:

```bash
yarn test
```

5. Debug a function

```bash
forge run --debug src/MyContract.sol --sig "someFunction()"
```

6. Print a gas report

```bash
yarn test:gas
```

7. Update Foundry periodically:

```bash
foundryup
```

Resources:

- [Forge guide](https://onbjerg.github.io/foundry-book/forge)
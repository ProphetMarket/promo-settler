# Promo Settler

`PromoSettler` pays a promotional USDC credit and settles the trade it funds in one transaction on Polygon. Prophet's operator calls `settle` in place of `matchOrders` on ProphetCTFExchange for a trade that spends a credit. The settler pulls the credit from the promo wallet to the user's Safe, forwards the match unchanged, and forwards every exchange fee to the operator. If the match fails, the credit payment fails with it.

A record for each Safe and promo code fixes the credit total at the first settlement. The sum of settled amounts can never pass that total, whatever the server sends.

## What this repository holds

| Path | What it is |
|---|---|
| `src/PromoSettler.sol` | The settler: `settle`, the credit records, the admin and operator registry, the credit maximum, the pause, and token recovery to the promo wallet |
| `script/Deploy.s.sol` | Deploys the settler to Polygon mainnet or Amoy from five environment values |
| `script/DeployLocal.s.sol` | Deploys, registers, funds, and publishes the settler on the server's local Anvil chain |
| `DEPLOYMENT.md` | The deploy runbook, the two follow-up actions by other keys, and the checks |
| `specs/` | The features, use cases, and architecture this code implements |
| `test/features/` | Integration tests, one file per use case, over the real exchange and Conditional Tokens bytecode |

## Build and test

The ctf-exchange submodule supplies the exchange's `Order` struct. Fetch it once after cloning:

```shell
git submodule update --init --recursive
```

Then build and test:

```shell
forge build
forge test
forge coverage
```

`forge fmt` formats the Solidity sources. Every source pins `pragma solidity 0.8.24;`.

## Deploy

See `DEPLOYMENT.md`. Signing uses Foundry's CLI flags. No script reads a private key.

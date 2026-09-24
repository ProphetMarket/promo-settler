# Deployment Guide

This guide deploys `PromoSettler` to Polygon mainnet (chain ID 137) or Polygon Amoy (chain ID 80002). After the deploy, two other keys each perform one action: the exchange admin registers the settler, and the promo wallet approves it. A check follows each step.

The exchange and USDC addresses below come from the lp-vaults deployment guide, which read them from both chains on 2026-09-15. The chain is the source of truth, so run the checks in section 6 before you trust a value.

## 1. What you deploy

One run of `script/Deploy.s.sol` deploys one contract, `PromoSettler`. The operator calls its `settle` function in place of `matchOrders` on the exchange for a trade that spends a promotional credit. The settler pays the credit from the promo wallet to the user's Safe and forwards the match in the same transaction.

The settler stores four values that no function can change:

| Value | Source | Why it must be exact |
|---|---|---|
| `exchange` | `EXCHANGE_ADDRESS` | The settler forwards every match to it and checks every caller against its operator list. |
| `promoWallet` | `PROMO_WALLET_ADDRESS` | The settler pulls every credit from it and sends every recovered token to it. |
| `usdc` | the exchange's `getCollateral()` | The settler reads it at deployment, so it always equals the exchange's collateral. |
| `ctf` | the exchange's `getCtf()` | The settler accepts outcome shares only from it. |

A wrong exchange or promo wallet needs a new settler.

## 2. Network reference

| Item | Polygon mainnet (137) | Polygon Amoy (80002) |
|---|---|---|
| `EXCHANGE_ADDRESS` | `0x127aD3A6e55EbBDaecC0eaeb12615879611e1839` | `0x0D9BD7320985ee23c04885Ec93f6c118a83c7ec0` |
| USDC (the exchange's collateral) | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` (Circle native USDC) | `0x4b0a4ADc5349709D9111C473cf93e9Af30Fd5fA6` (Prophet's Test USD Coin) |
| Block explorer | https://polygonscan.com | https://amoy.polygonscan.com |

## 3. Wallets and roles

| Wallet | Variable | Job |
|---|---|---|
| Deployer | `DEPLOYER_ADDRESS` | Pays the deployment gas. The script gives it no role. |
| Admin | `ADMIN_ADDRESS` | Manages settler admins and operators, sets the credit maximum, pauses the settler, and recovers stray tokens to the promo wallet. |
| Operator | `OPERATOR_ADDRESS` | The server's operator EOA. Calls `settle`. Must also be an exchange operator. |
| Promo wallet | `PROMO_WALLET_ADDRESS` | Holds the campaign USDC and approves the settler for a finite allowance. |
| Exchange admin | — | Registers the settler as an exchange operator (section 5.1). |

## 4. Deploy

Build and test the commit you deploy:

```bash
forge build
forge test
```

Fill `.env` from `.env.example`, then load it:

```bash
set -a; source .env; set +a
```

Deploy. The script refuses a zero or missing value and names the variable in its error. It reads no private key: sign with `--account`, `--ledger`, or `--trezor`.

```bash
forge script script/Deploy.s.sol --sig "run()" \
  --account "$DEPLOYER_ACCOUNT" --sender "$DEPLOYER_ADDRESS" \
  --rpc-url "$RPC_URL" --broadcast --verify
```

The script logs the settler address and the USDC and Conditional Tokens addresses it read from the exchange. Record the settler address:

```bash
export SETTLER_ADDRESS=<the logged PromoSettler address>
```

## 5. Actions by other keys

### 5.1 The exchange admin registers the settler

The settler calls `matchOrders`, which the exchange allows only for its operators. The exchange admin runs `AddOperator.s.sol` from ProphetMarket/contracts, with the settler as the operator:

```bash
# In the ProphetMarket/contracts repository
EXCHANGE_ADDRESS=$EXCHANGE_ADDRESS OPERATOR_ADDRESS=$SETTLER_ADDRESS \
forge script script/AddOperator.s.sol --sig "run()" \
  --account <exchange-admin-account> --rpc-url "$RPC_URL" --broadcast
```

### 5.2 The promo wallet approves the settler

The allowance is the worst-case loss from a compromised operator key. Approve the unspent budget of the running campaigns, the sum of `promo_pools.remaining_units`. Never approve `type(uint256).max`. The promo wallet signs through KMS:

```text
USDC.approve(SETTLER_ADDRESS, <allowance in raw units>)
```

`approve(SETTLER_ADDRESS, 0)` stops every settlement in one transaction.

## 6. Checks

Run each check after its step. Each command prints the value in the "Expect" column.

| Step | Command | Expect |
|---|---|---|
| Deploy | `cast call $SETTLER_ADDRESS "exchange()(address)" --rpc-url $RPC_URL` | `EXCHANGE_ADDRESS` |
| Deploy | `cast call $SETTLER_ADDRESS "promoWallet()(address)" --rpc-url $RPC_URL` | `PROMO_WALLET_ADDRESS` |
| Deploy | `cast call $SETTLER_ADDRESS "usdc()(address)" --rpc-url $RPC_URL` | the USDC in section 2 |
| Deploy | `cast call $SETTLER_ADDRESS "operators(address)(uint256)" $OPERATOR_ADDRESS --rpc-url $RPC_URL` | `1` |
| Deploy | `cast call $SETTLER_ADDRESS "admins(address)(uint256)" $ADMIN_ADDRESS --rpc-url $RPC_URL` | `1` |
| Deploy | `cast call $SETTLER_ADDRESS "maxCreditUnits()(uint128)" --rpc-url $RPC_URL` | `MAX_CREDIT_UNITS` |
| 5.1 | `cast call $EXCHANGE_ADDRESS "isOperator(address)(bool)" $SETTLER_ADDRESS --rpc-url $RPC_URL` | `true` |
| 5.1 | `cast call $EXCHANGE_ADDRESS "isOperator(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL` | `true` |
| 5.2 | `cast call <USDC> "allowance(address,address)(uint256)" $PROMO_WALLET_ADDRESS $SETTLER_ADDRESS --rpc-url $RPC_URL` | the approved allowance |

## 7. Operations

| Task | Who | Call |
|---|---|---|
| Stop every settlement | Admin | `pause()` (or the promo wallet signs `approve(settler, 0)`) |
| Restart settlement | Admin | `unpause()` |
| Change the credit maximum for new credits | Admin | `setMaxCreditUnits(newValue)` |
| Add or remove an operator | Admin | `addOperator(address)`, `removeOperator(address)`. The exchange must also list a new operator. |
| Move stray USDC or shares to the promo wallet | Admin | `recover(0)` for USDC, `recover(tokenId)` for an outcome token |
| Read a credit record | Anyone | `credits(safe, codeId)` returns `total` and `spent` |

## 8. Local Anvil

The server's integration harness deploys the settler with `script/DeployLocal.s.sol`, as the third step of its `make deploy-local`. That script registers the settler on the local exchange, funds and approves the promo wallet, and writes `promoSettler` into the local addresses file. The server's `contracts/Makefile` owns the command.

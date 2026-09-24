---
id: UC-UFXZ
name: Deploy the Settler to Local Anvil
feature: FEAT-UFXU
status: implemented
version: 1
actor: Deployer
---

# UC-UFXZ: Deploy the Settler to Local Anvil

> The deployer gives the server's local harness a settler that is registered, funded, approved, and listed beside the other local addresses.

## Preconditions

- The server's meta project deployed the local stack and wrote an addresses file with the keys `exchange`, `usdc`, and `deployer`.
- The deployer is the exchange admin and the owner of the local USDC.

## Trigger

The server's `contracts/Makefile` runs `forge script script/DeployLocal.s.sol --sig "run()"` from `lib/promo-settler`, or a test calls `run(deployer)` or `run(deployer, cfg)`.

---

### SC-UFYU: The local deploy registers, funds, approves, and publishes the settler

**Given:**
- The chain ID is 80002.
- A `LocalConfig` with the addresses file path, the exchange, a promo wallet, `maxCreditUnits = 10,000,000`, and `localPromoFundUnits = 100,000,000`.

**Steps:**
1. Deployer calls `run(deployer, cfg)`.
2. System deploys the settler with the deployer as admin and operator.
3. System calls `exchange.addOperator(settler)` as the deployer.
4. System mints 100,000,000 units of the settler's `usdc()`, which the settler read from the exchange, to the promo wallet as the deployer.
5. System approves the settler for 100,000,000 units as the promo wallet.
6. System writes the settler's address into the addresses file under `promoSettler`.

**Outcomes:**
- `exchange.isOperator(settler) = true`.
- The promo wallet holds 100,000,000 units, and `allowance(promoWallet, settler) = 100,000,000`.
- The file's `promoSettler` equals the settler, and `exchange`, `usdc`, and `deployer` keep their values.

**Side Effects:**
- `NewOperator(settler, deployer)` event emitted by the exchange.
- USDC `Approval` from the promo wallet to the settler.

---

### SC-UFYV: The local deploy reads its configuration from the addresses file and the environment

**Given:**
- The environment sets `ADDRESSES_JSON_PATH`, `PROMO_WALLET_ADDRESS`, `MAX_CREDIT_UNITS`, and `LOCAL_PROMO_FUND_UNITS`.
- The addresses file holds `exchange`, `usdc`, and `deployer`.

**Steps:**
1. Deployer calls `run(deployer)`.
2. System reads the exchange and the deployer from the file and the other values from the environment, then deploys as in SC-UFYU.

**Outcomes:**
- The file's `promoSettler` equals the deployed settler.

**Side Effects:**
- No private key read from the environment.

---

### SC-UFYW: The local deploy refuses a chain other than Amoy

**Given:**
- The chain ID is 137.

**Steps:**
1. Deployer calls `run(deployer, cfg)`.
2. System reverts with `UnexpectedChainId(137, 80002)`.

**Outcomes:**
- No settler exists, and the addresses file is unchanged.

**Side Effects:**
- No contract created.
- No exchange role changes and no USDC minted.

---
id: UC-UFXY
name: Deploy the Settler to Polygon
feature: FEAT-UFXU
status: implemented
version: 1
actor: Deployer
---

# UC-UFXY: Deploy the Settler to Polygon

> The deployer creates a settler whose exchange, promo wallet, roles, and credit maximum match the configuration.

## Preconditions

- ProphetCTFExchange is deployed on the target chain (137 or 80002) and answers `getCollateral()` and `getCtf()`.

## Trigger

The deployer runs `forge script script/Deploy.s.sol --sig "run()"` with signing flags, or a test calls `run(deployer)` or `run(deployer, cfg)`.

---

### SC-UFYR: Deploy with a complete configuration

**Given:**
- A `DeployConfig` with the exchange, a promo wallet, an admin, an operator, and `maxCreditUnits = 10,000,000`.

**Steps:**
1. Deployer calls `run(deployer, cfg)`.
2. System validates every value and deploys the settler.

**Outcomes:**
- The settler's `exchange()` and `promoWallet()` equal the configuration.
- The settler's `usdc()` equals `exchange.getCollateral()`, and `ctf()` equals `exchange.getCtf()`.
- `admins(admin) = 1`, `adminCount() = 1`, `operators(operator) = 1`, and `maxCreditUnits() = 10,000,000`.
- `paused() = false`.

**Side Effects:**
- One contract created.
- No exchange role changes and no USDC approval.

---

### SC-UFYS: Deploy reads its configuration from the environment

**Given:**
- The environment sets `EXCHANGE_ADDRESS`, `PROMO_WALLET_ADDRESS`, `ADMIN_ADDRESS`, `OPERATOR_ADDRESS`, and `MAX_CREDIT_UNITS = 10000000`.

**Steps:**
1. Deployer calls `run(deployer)`.
2. System reads the five values in `_configFromEnv` and deploys.

**Outcomes:**
- The deployed settler carries the five environment values.

**Side Effects:**
- No private key read from the environment.

---

### SC-UFYT: A missing, zero, or out-of-range value is refused

**Given:**
- A configuration with one zero value.

**Steps:**
1. Deployer calls `run(deployer, cfg)` with `exchange = address(0)`, then `promoWallet`, `admin`, and `operator` zero in turn.
2. System reverts with `ZeroAddress("EXCHANGE_ADDRESS")`, `ZeroAddress("PROMO_WALLET_ADDRESS")`, `ZeroAddress("ADMIN_ADDRESS")`, and `ZeroAddress("OPERATOR_ADDRESS")`.
3. Deployer calls `run(deployer, cfg)` with `maxCreditUnits = 0`.
4. System reverts with `ZeroMaxCreditUnits()`.
5. Deployer calls `run(deployer, cfg)` with `maxCreditUnits = 2^128`, one above the largest `uint128`.
6. System reverts with `MaxCreditUnitsTooLarge()`, before a narrowing cast could wrap the value to 0.
7. A caller deploys `PromoSettler` directly with a zero address or a zero maximum.
8. The constructor reverts with `ZeroAddress()` or `ZeroMaxCredit()`.

**Outcomes:**
- No settler exists after a refused deploy.

**Side Effects:**
- No contract created.

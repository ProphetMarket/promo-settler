# Tech Stack

## Modules

### contracts
- **Directory:** `.`
- **Language:** Solidity 0.8.24 (`pragma solidity 0.8.24;` in every source; `solc_version = "0.8.24"` in `foundry.toml`)
- **Framework:** Foundry (forge, cast, anvil)
- **Build:** `forge build`
- **Key libraries:** forge-std (test and script only); ctf-exchange at `9e6d895` through the remapping `exchange/=lib/ctf-exchange/src/exchange/` (the `Order` struct and its `Side` and `SignatureType` enums only)
- **Testing:** forge test (integration tests driven through the settler's functions and the deploy scripts' `run` overloads, plus fuzz tests)
- **Running tests:** `forge test`
- **Coverage:** `forge coverage`
- **Lint/Format:** `forge fmt`

## Runtime
- **Type:** host-native
- **Start command:** `forge build`
- **Stop command:** N/A

## Services

N/A -- pure contract project with no runtime services.

## Applications

| Application | Type | Port/Target | Run Command | Notes |
|-------------|------|-------------|-------------|-------|
| contracts | smart contract | Polygon | `forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast` | Called by Prophet's server operator wallet in place of a direct call to ProphetCTFExchange |

## External Services
- Polygon (deployment target chain; mainnet is chain id 137, tests run against non-forking Anvil at chain id 80002, Polygon Amoy)
- ProphetCTFExchange (the on-chain order-matching contract the settler forwards trades to)
- The user's Gnosis Safe wallet (holds the USDC the settler funds and the Exchange pulls)

## Repository Structure
- **Type:** single-repo (planned to join `~/Code/Prophet/prophet`'s Foundry meta-project as a git submodule once built)
- **Package manager:** N/A (Foundry manages dependencies via git submodules in `lib/`)

## Tooling

| Module | Root | Language | Format Command | Lint Command |
|--------|------|----------|----------------|--------------|
| contracts | `.` | Solidity | `forge fmt` | `forge fmt --check` |

## Environment
- **Env file:** `.env`
- **Key variables:** `EXCHANGE_ADDRESS`, `PROMO_WALLET_ADDRESS`, `ADMIN_ADDRESS`, `OPERATOR_ADDRESS`, `MAX_CREDIT_UNITS` (read by `script/Deploy.s.sol`); `ADDRESSES_JSON_PATH`, `PROMO_WALLET_ADDRESS`, `MAX_CREDIT_UNITS`, `LOCAL_PROMO_FUND_UNITS` (read by `script/DeployLocal.s.sol`, which also reads `exchange` and `deployer` from the addresses file)
- **Seed data:** N/A

## Conventions
- Pin `pragma solidity 0.8.24;` exactly. Compile with zero warnings.
- Declare the ERC-20, ERC-1155, and exchange interfaces inline. Import no implementation library into `src/`.
- Add a dependency only with `forge install`, and only when asked to run it.
- One deploy-script config function, `_configFromEnv`, returns a struct every other deploy step reads. A `run(deployer, cfg)` overload lets a test build the struct directly, without reading the environment.
- Integration test files follow `test/features/{FEAT-dir}/{UC-dir}.t.sol`, matching the sibling `lp-vaults` repository.
- Run `forge fmt` and `forge build` after every change. Run `forge test` before calling a change done.

# Tech Stack

## Modules

### contracts
- **Directory:** `.`
- **Language:** Solidity (pin the exact compiler version once design settles; not fixed yet)
- **Framework:** Foundry (forge, cast, anvil)
- **Build:** `forge build`
- **Key libraries:** forge-std (test-only); production dependencies are added only through `forge install`, decided during design
- **Testing:** forge test (unit + fuzz; add invariant tests if the design calls for one)
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
- **Key variables:** set by the deploy script's single `_configFromEnv` function; the exact variables are decided during design
- **Seed data:** N/A

## Conventions
- Pin `pragma solidity` to one exact compiler version once chosen. Compile with zero warnings.
- Add a dependency only with `forge install`, and only when asked to run it.
- One deploy-script config function, `_configFromEnv`, returns a struct every other deploy step reads. A `run(deployer, cfg)` overload lets a test build the struct directly, without reading the environment.
- Integration test files follow `test/features/{FEAT-dir}/{UC-dir}.t.sol`, matching the sibling `lp-vaults` repository.
- Run `forge fmt` and `forge build` after every change. Run `forge test` before calling a change done.

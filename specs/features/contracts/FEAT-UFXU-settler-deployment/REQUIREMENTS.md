---
id: FEAT-UFXU
name: Settler Deployment
module: contracts
domain: admin
status: implemented
version: 1
refs: [FEAT-UFXS, FEAT-UFXT]
---

# Settler Deployment

> The deployer creates the settler on Polygon from environment values, and on the local Anvil chain with its registration, funding, and published address.

## Non-Goals

- Does not register the settler on the mainnet or Amoy exchange. The exchange admin runs `AddOperator.s.sol` in ProphetMarket/contracts, as `DEPLOYMENT.md` lists.
- Does not approve the settler from the mainnet or Amoy promo wallet. The promo wallet signs `approve` through KMS, as `DEPLOYMENT.md` lists.
- Does not deploy the exchange, USDC, the Conditional Tokens contract, or the Safe factory.
- Does not change the server's Makefile or bindings. The server repository consumes the published address and the ABI.

## Actors

| Actor | Role | Notes |
|-------|------|-------|
| Deployer | Runs `script/Deploy.s.sol` or `script/DeployLocal.s.sol` | Signs through Foundry's CLI flags |
| Promo Wallet | Approves the settler in the local deploy | Signs with its local Anvil key, passed as a second `--private-keys` value |

## Functional Requirements

**FR-UFZ5** `If a deploy value is zero or missing, then the deploy script shall revert with an error that names the value.`
Fit Criterion: Given a configuration with `promoWallet = address(0)`, `run(deployer, cfg)` reverts with `ZeroAddress("PROMO_WALLET_ADDRESS")` and deploys nothing.
Linked to: UC-UFXY

**FR-UFZ6** `When the local deploy completes, the deploy script shall write the settler's address into the addresses file under the key promoSettler.`
Fit Criterion: Given an addresses file with `exchange`, `usdc`, and `deployer`, after the local deploy `vm.parseJsonAddress(file, ".promoSettler")` equals the deployed settler and the three earlier keys keep their values.
Linked to: UC-UFXZ

## Non-Functional Requirements

**NFR-UFZ8** Security: `The deploy scripts shall read no private key from the environment.`
Fit Criterion: Given the two scripts, no call to `vm.envUint`, `vm.envBytes32`, or `vm.envString` reads a key, and every broadcast uses `vm.startBroadcast()` or `vm.startBroadcast(address)`.

## Acceptance

> The feature is complete when all of the following are true:

- Every scenario of deploy the settler to Polygon (UC-UFXY) and deploy the settler to local Anvil (UC-UFXZ) passes its integration test.
- `DEPLOYMENT.md` and `.env.example` list every value the scripts read.
- ARCHITECTURE.md diagrams reflect the built system.
- FEATURES.md status is `implemented`.

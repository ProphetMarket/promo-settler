# Actors

> Roles that interact with this system. Referenced by use cases and requirements.

| Actor | Role | Description | Constraints |
|-------|------|-------------|-------------|
| Operator | system | Prophet's server, signing through AWS KMS (a cloud key-management service that signs transactions without exposing the private key). Calls the settler's `settle` in place of calling `matchOrders` on ProphetCTFExchange directly, for a trade that spends a promotional credit | The only caller `settle` accepts. Must be registered as an operator on both the settler and ProphetCTFExchange. Receives every fee the exchange charges on a settled trade |
| User | human | The trading user. Holds a Gnosis Safe wallet, named as `maker` on the credited order, which is the taker order or one maker order. Receives the promotional credit and is the account ProphetCTFExchange pulls USDC from | Never calls the settler directly. The settler reads the recipient from the signed credited order, never from a separate parameter |
| Admin | human | Manages the settler's admins and operators, sets the credit maximum, pauses and unpauses settlement, and recovers stray tokens to the promo wallet | Cannot call `settle` as an admin. Cannot send recovered tokens to any address other than the promo wallet |
| ProphetCTFExchange | system | The on-chain order-matching contract (a Polymarket CTF Exchange fork) that the settler forwards the trade to after paying the credit | External contract; the settler must forward the orders it receives without altering them |
| Deployer | human | Runs the deploy scripts that create the settler on Polygon and on the local Anvil chain | Signs through Foundry's CLI flags. The scripts read no private key from the environment |
| Promo Wallet | system | The EOA that holds the campaign's USDC, controlled by the server's KMS promo key. Approves the settler for a finite USDC allowance | Signs only `approve`. The settler pulls each credit from it with `transferFrom` |

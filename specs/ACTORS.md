# Actors

> Roles that interact with this system. Referenced by use cases and requirements.

| Actor | Role | Description | Constraints |
|-------|------|-------------|-------------|
| Operator | system | Prophet's server, signing through AWS KMS (a cloud key-management service that signs transactions without exposing the private key). Calls the settler in place of calling `matchOrders` on ProphetCTFExchange directly | The only caller the settler accepts; must itself be registered as an operator on ProphetCTFExchange for its forwarded call to succeed |
| User | human | The trading user. Holds a Gnosis Safe wallet, named as `maker` on the taker order. Receives the promotional credit and is the account ProphetCTFExchange pulls USDC from | Never calls the settler directly; the settler reads the recipient from the order the Operator submits, never as a separate parameter |
| Admin | human | Manages the settler's operational controls: pausing it and withdrawing its funds to a named address | Exact authority and functions are decided during design |
| ProphetCTFExchange | system | The on-chain order-matching contract (a Polymarket CTF Exchange fork) that the settler forwards the trade to after paying the credit | External contract; the settler must forward the orders it receives without altering them |

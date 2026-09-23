# Glossary

> Canonical definitions for all terms used in specs.
> Every agent reads this before any other document.

## Terms

**Module** -- A physical application layer that maps to a deployable unit. In this project there is one module: the Solidity contract.

**Domain Tag** -- A logical business concern that crosses module boundaries. Used to categorize features and use cases (e.g., @settlement, @admin).

**Feature** -- A user-facing capability described in a spec. Features accumulate use cases over their lifetime.

**Use Case** -- A single interaction scenario within a feature, with defined preconditions, steps, and postconditions.

**Actor** -- A role that interacts with the system: Operator, User, Admin, or ProphetCTFExchange.

**Promotional Credit** -- The USDC amount Prophet grants a new user, recorded in Prophet's Postgres database and paid on-chain by the settler at trade time.

**Taker Order** -- The order the trading user's Gnosis Safe wallet signs to buy or sell an outcome token. Its `maker` field names the Safe that ProphetCTFExchange pulls USDC from, and the settler reads the credit recipient from this field.

**matchOrders** -- The function on ProphetCTFExchange that settles a taker order against one or more maker orders. The settler forwards its call to this function, unchanged, after paying the credit.

**Gnosis Safe** -- The smart contract wallet that holds a user's USDC. Prophet deploys one per user through a Safe factory. The Exchange pulls the taker's USDC from this address, not from the user's own EOA (externally owned account, a wallet controlled directly by a private key).

**Atomic Transaction** -- A blockchain transaction whose effects (here, the credit payment and the trade settlement) either all happen or none happen. If the trade settlement reverts, the credit payment reverts with it.

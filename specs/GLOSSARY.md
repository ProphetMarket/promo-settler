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

**Taker Order** -- The order that `matchOrders` matches against one or more maker orders. ProphetCTFExchange pulls the taker order's making amount from the address in its `maker` field.

**matchOrders** -- The function on ProphetCTFExchange that settles a taker order against one or more maker orders. The settler forwards its call to this function, unchanged, after paying the credit.

**Gnosis Safe** -- The smart contract wallet that holds a user's USDC. Prophet deploys one per user through a Safe factory. The Exchange pulls the taker's USDC from this address, not from the user's own EOA (externally owned account, a wallet controlled directly by a private key).

**Atomic Transaction** -- A blockchain transaction whose effects (here, the credit payment and the trade settlement) either all happen or none happen. If the trade settlement reverts, the credit payment reverts with it.

**Credited Order** -- The signed order whose maker receives the promotional credit. It is the taker order or one maker order, as the Operator's `creditedIndex` selects: 0 names the taker order, and `i + 1` names `makerOrders[i]`. It must be a BUY signed with the `POLY_GNOSIS_SAFE` signature type.

**Promo Code ID** -- The 32-byte identifier of the promo code a user redeemed: the database UUID `referral_codes.id`, written as `bytes32(uint256(uint128(uuid)))`.

**Credit Record** -- The settler's on-chain record for one Safe and one promo code ID. It holds the credit total and the amount spent so far. Example: a total of 5,000,000 units and 2,000,000 units spent leave 3,000,000 units to pay.

**Credit Total** -- The full credit for one Safe and one promo code ID, in USDC raw units (1,000,000 units = $1.00). The first settlement for that pair fixes it, and it never changes after that.

**Credit Maximum** -- The admin-set ceiling, `maxCreditUnits`, on the credit total that a first settlement may record.

**Promo Wallet** -- The EOA that funds every credit. The settler pulls each credit from it with `transferFrom`, within the allowance the promo wallet approved.

**Fee** -- The charge ProphetCTFExchange takes on a fill, paid to the caller of `matchOrders`. For a settled trade that caller is the settler, which forwards every fee to the Operator.

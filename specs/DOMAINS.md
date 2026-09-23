# Domains

> Logical business concerns that cross module boundaries.
> Use domain tags on features and use cases to filter by business area
> (e.g., list every feature under @settlement across all modules).

| ID | Domain | Description |
|----|--------|-------------|
| @settlement | Credit and Trade Settlement | Paying the promotional USDC credit and forwarding the trade to ProphetCTFExchange in one transaction, so a credit is paid exactly once and only when its trade settles |
| @admin | Operational Controls | Pausing the settler and withdrawing its funds to a named address |

# Project

> A Foundry smart contract that pays a promotional USDC credit and settles the trade it funds in one transaction.

Prophet grants a new user a one-time promotional USDC credit, recorded in Prophet's Postgres database, then pays that credit from a promo wallet when the user places their first trade. Two off-chain designs to pay the credit have failed. The first design over-paid: a timed-out wait let a request retry while an earlier payment was still pending in the mempool (a queue of transactions waiting to be added to the blockchain). The second design stopped the over-payment, but paid too late for the trade it was meant to fund, because the payment and the trade were two separate transactions.

This project builds a settler contract that combines the credit payment and the trade settlement into one transaction on the Polygon blockchain. Prophet's server calls the settler instead of calling the CTF Exchange (ProphetCTFExchange, Prophet's on-chain order-matching contract) directly. The settler pays the promotional credit to the trading user's Gnosis Safe wallet, then forwards the trade to the Exchange in the same call. The credit reaches the wallet only when the trade it funds settles, and a reverted trade leaves the credit unspent for a retry.

This repository holds the contract and its deploy scripts. The promo wallet funds each credit through a finite USDC allowance to the settler. A record per Safe and promo code caps each credit on chain, and an admin-set maximum caps each credit total. The Operator reaches the exchange through the settler only for a trade that spends a credit.

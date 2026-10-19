
# Elysium Arena

**Paper-trading competitions with risk-adjusted scoring on the Elysium testnet.**

> Rank traders by skill, not luck.

## One-sentence pitch

Elysium Arena is a paper-trading competition platform where players are ranked by **return ÷ worst drawdown** instead of raw profit.

## Why this exists

Most trading contests just ask “who made the most money?”  
That rewards oversized, lucky bets.

Arena ranks by risk-adjusted performance:

score = return_bps × 10000 / max(maxDrawdownBps, 100)

A trader who makes +20% while never dropping more than 5% beats someone who made +40% after a 30% drawdown.

## Important note

This is a **simulated market**.  
Prices are controlled by the project (PriceFeed contract).  
Nothing trades on a real order book or reads live HyperCore data yet.  
This is clearly labeled in the product and demos.

## Core features (MVP)

- Timed contests
- Same starting virtual cash for every player
- Paper trading against 3 assets
- Live risk-adjusted scoring
- Exposure cap (2× equity)
- closeContest freezes final prices (owner cannot manipulate after end)
- Winner-takes-all prize pool
- Max 16 players per contest

## Token plans

We intend to launch a lightweight utility token on Elysium mainnet after the product has real usage.  
The token will be used for contest creation rights, fee sharing, and governance of scoring parameters.  
The product is designed to be useful without a token.

## Status

Core contracts are written and patched.  
Ready for testnet deployment and demo.
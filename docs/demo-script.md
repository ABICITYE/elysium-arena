# Elysium Arena – Demo Script

**Goal:** Show a complete paper-trading contest with risk-adjusted scoring in under 5 minutes.

## Pre-requisites

- Two (or more) wallets funded with test HYPE on Elysium testnet
- Contracts deployed (Arena + PriceFeed)
- Updater script running (or manual price updates)

## Demo flow

1. **Show the banner**  
   “Simulated market. Prices are set by the project. This is paper trading.”

2. **Create a short contest** (owner)  
   - Duration: 10–15 minutes  
   - Start cash: 10 000  
   - Entry fee: small amount of test HYPE  
   - Max players: 4–8  

3. **Join with two wallets**  
   - Wallet A and Wallet B both join and pay the entry fee.

4. **Update prices a few times**  
   - Move the three assets around so the market is alive.

5. **Trade**  
   - Wallet A takes a conservative long.  
   - Wallet B takes a more aggressive position.  
   - Show live equity and score updating.

6. **Poke / mark**  
   - Demonstrate that drawdown is being recorded.

7. **End the contest**  
   - Call `closeContest` then `finalize`.  
   - Show that the winner is the one with the better return / drawdown ratio, **not** necessarily the highest raw profit.

8. **Claim**  
   - Winner claims the prize pool.

## Talking points

- Why risk-adjusted scoring beats raw PnL contests.
- Why a simulated feed is honest on today’s testnet (no HyperCore reads yet).
- Everything is on-chain and verifiable.
- Future path: once HyperCore precompiles land, the same scoring engine can sit on top of real positions.

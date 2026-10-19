/**
 * Simple price updater + poke script for Elysium Arena
 * 
 * Run with:
 *   node scripts/updater.js
 * 
 * Requires: PRICE_FEED_ADDRESS, ARENA_ADDRESS, PRIVATE_KEY, RPC_URL
 */

const { createPublicClient, createWalletClient, http, parseAbi } = require("viem");
const { privateKeyToAccount } = require("viem/accounts");

const RPC_URL = process.env.RPC_URL || "https://testnet-rpc.elysium.kinetiq.xyz";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const PRICE_FEED_ADDRESS = process.env.PRICE_FEED_ADDRESS;
const ARENA_ADDRESS = process.env.ARENA_ADDRESS;
const CONTEST_ID = Number(process.env.CONTEST_ID || 1);

const ASSETS = [0, 1, 2];
const BASE_PRICES = [100_00000000n, 50_00000000n, 25_00000000n];

async function main() {
  if (!PRIVATE_KEY || !PRICE_FEED_ADDRESS || !ARENA_ADDRESS) {
    console.error("Set PRIVATE_KEY, PRICE_FEED_ADDRESS, ARENA_ADDRESS");
    process.exit(1);
  }

  const account = privateKeyToAccount(PRIVATE_KEY);
  const publicClient = createPublicClient({ transport: http(RPC_URL) });
  const walletClient = createWalletClient({
    account,
    transport: http(RPC_URL),
  });

  const priceFeedAbi = parseAbi([
    "function setPrice(uint256 assetId, uint256 price)",
    "function getPrice(uint256 assetId) view returns (uint256 price, uint256 timestamp)",
  ]);

  const arenaAbi = parseAbi([
    "function poke(uint256 contestId, address player)",
    "function getContestPlayers(uint256 contestId) view returns (address[])",
  ]);

  console.log("Updater started. Owner:", account.address);

  for (const assetId of ASSETS) {
    const jitter = BigInt(Math.floor(Math.random() * 5_00000000) - 2_50000000);
    const newPrice = BASE_PRICES[assetId] + jitter;
    const hash = await walletClient.writeContract({
      address: PRICE_FEED_ADDRESS,
      abi: priceFeedAbi,
      functionName: "setPrice",
      args: [BigInt(assetId), newPrice],
    });
    console.log(`setPrice asset ${assetId} → ${newPrice}  tx: ${hash}`);
  }

  const players = await publicClient.readContract({
    address: ARENA_ADDRESS,
    abi: arenaAbi,
    functionName: "getContestPlayers",
    args: [BigInt(CONTEST_ID)],
  });

  for (const player of players) {
    const hash = await walletClient.writeContract({
      address: ARENA_ADDRESS,
      abi: arenaAbi,
      functionName: "poke",
      args: [BigInt(CONTEST_ID), player],
    });
    console.log(`poked ${player}  tx: ${hash}`);
  }

  console.log("Done.");
}

main().catch(console.error);

/**
 * Deploy script for Elysium Arena
 * 
 * Usage:
 *   npx hardhat run scripts/deploy.js --network elysiumTestnet
 */

const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  // 1. Deploy PriceFeed
  const PriceFeed = await hre.ethers.getContractFactory("PriceFeed");
  const priceFeed = await PriceFeed.deploy();
  await priceFeed.waitForDeployment();
  const priceFeedAddress = await priceFeed.getAddress();
  console.log("PriceFeed deployed to:", priceFeedAddress);

  // 2. Deploy Arena
  const Arena = await hre.ethers.getContractFactory("Arena");
  const arena = await Arena.deploy(priceFeedAddress);
  await arena.waitForDeployment();
  const arenaAddress = await arena.getAddress();
  console.log("Arena deployed to:", arenaAddress);

  // 3. Set initial prices
  const tx0 = await priceFeed.setPrice(0, 100_00000000n);
  await tx0.wait();
  const tx1 = await priceFeed.setPrice(1, 50_00000000n);
  await tx1.wait();
  const tx2 = await priceFeed.setPrice(2, 25_00000000n);
  await tx2.wait();
  console.log("Initial prices set");

  console.log("\n=== Deployment complete ===");
  console.log("PriceFeed:", priceFeedAddress);
  console.log("Arena:    ", arenaAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

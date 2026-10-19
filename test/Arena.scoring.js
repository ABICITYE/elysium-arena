const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Arena – patched version", function () {
  let priceFeed, arena, owner, player1, player2;

  const START_CASH = ethers.parseEther("10000");
  const DURATION = 3600;
  const ENTRY_FEE = 0n;

  beforeEach(async function () {
    [owner, player1, player2] = await ethers.getSigners();

    const PriceFeed = await ethers.getContractFactory("PriceFeed");
    priceFeed = await PriceFeed.deploy();
    await priceFeed.waitForDeployment();

    const Arena = await ethers.getContractFactory("Arena");
    arena = await Arena.deploy(await priceFeed.getAddress());
    await arena.waitForDeployment();

    await priceFeed.setPrice(0, 100_00000000n);
    await priceFeed.setPrice(1, 50_00000000n);
    await priceFeed.setPrice(2, 25_00000000n);
  });

  async function createAndJoin() {
    await arena.createContest(DURATION, START_CASH, ENTRY_FEE, 8);
    await arena.connect(player1).join(1, { value: ENTRY_FEE });
    await arena.connect(player2).join(1, { value: ENTRY_FEE });
  }

  it("creates contest and lets players join", async function () {
    await createAndJoin();
    const p1 = await arena.getPlayer(1, player1.address);
    expect(p1.joined).to.be.true;
    expect(p1.cash).to.equal(START_CASH);
  });

  it("blocks admin from joining", async function () {
    await arena.createContest(DURATION, START_CASH, ENTRY_FEE, 8);
    await expect(
      arena.connect(owner).join(1, { value: ENTRY_FEE })
    ).to.be.revertedWithCustomError(arena, "AdminCannotJoin");
  });

  it("allows reducing a position even when over 2x cap", async function () {
    await createAndJoin();
    const bigSize = ethers.parseEther("150");
    await arena.connect(player1).trade(1, 0, bigSize);
    await priceFeed.setPrice(0, 90_00000000n);
    await arena.poke(1, player1.address);
    const reduceSize = ethers.parseEther("-50");
    await expect(arena.connect(player1).trade(1, 0, reduceSize)).to.not.be.reverted;
  });

  it("rejects a trade that increases exposure while over 2x", async function () {
    await createAndJoin();
    const bigSize = ethers.parseEther("150");
    await arena.connect(player1).trade(1, 0, bigSize);
    await priceFeed.setPrice(0, 90_00000000n);
    await arena.poke(1, player1.address);
    await expect(
      arena.connect(player1).trade(1, 0, ethers.parseEther("10"))
    ).to.be.revertedWithCustomError(arena, "ExposureExceeded");
  });

  it("closeContest freezes prices and blocks further poke/trade", async function () {
    await createAndJoin();
    await time.increase(DURATION + 1);
    await arena.closeContest(1);
    const finalPrices = await arena.getFinalPrices(1);
    expect(finalPrices[0]).to.equal(100_00000000n);
    await expect(arena.poke(1, player1.address))
      .to.be.revertedWithCustomError(arena, "PokeAfterClose");
  });

  it("full flow: close → finalize → claim", async function () {
    const fee = ethers.parseEther("0.1");
    await arena.createContest(DURATION, START_CASH, fee, 8);
    await arena.connect(player1).join(1, { value: fee });
    await arena.connect(player2).join(1, { value: fee });
    await arena.connect(player1).trade(1, 0, ethers.parseEther("10"));
    await priceFeed.setPrice(0, 110_00000000n);
    await arena.poke(1, player1.address);
    await time.increase(DURATION + 1);
    await arena.closeContest(1);
    await arena.finalize(1);
    const contest = await arena.contests(1);
    expect(contest.winner).to.equal(player1.address);
  });
});

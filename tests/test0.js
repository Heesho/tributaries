const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
const divDec = (amount, decimals = 18) => amount / 10 ** decimals;
const divDec6 = (amount, decimals = 6) => amount / 10 ** decimals;
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { execPath } = require("process");

const AddressZero = "0x0000000000000000000000000000000000000000";
const one = convert("1", 18);
const two = convert("2", 18);
const five = convert("5", 18);
const oneHundred = convert("100", 18);

let owner, user0, user1, user2;
let deriFactory, tribFactory;

describe("local: test0", function () {
  before("Initial set up", async function () {
    console.log("Begin Initialization");

    [owner, user0, user1, user2] = await ethers.getSigners();

    const deriFactoryArtifact = await ethers.getContractFactory(
      "DerivativeFactory"
    );
    deriFactory = await deriFactoryArtifact.deploy();

    const tribFactoryArtifact = await ethers.getContractFactory(
      "TributaryFactory"
    );
    tribFactory = await tribFactoryArtifact.deploy();

    console.log("Initialization Complete");
    console.log();
  });

  it("First Test", async function () {
    console.log("******************************************************");
  });
});

const { ethers } = require("hardhat");
const { utils, BigNumber } = require("ethers");
const hre = require("hardhat");
const AddressZero = "0x0000000000000000000000000000000000000000";

// Constants
const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay));
const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);

// Contract Variables
let deriFactory, tribFactory;

/*===================================================================*/
/*===========================  CONTRACT DATA  =======================*/

async function getContracts() {
  console.log("Retrieving Contracts");
  // deriFactory = await ethers.getContractAt(
  //   "contracts/DerivativeFactory.sol:DerivativeFactory",
  //   ""
  // );
  // tribFactory = await ethers.getContractAt(
  //   "contracts/TributaryFactory.sol:TributaryFactory",
  //   ""
  // );
  console.log("Contracts Retrieved");
}

/*===========================  END CONTRACT DATA  ===================*/
/*===================================================================*/

async function deployDerivativeFactory() {
  console.log("Starting Derivative Factory Deployment");
  const deriFactoryArtifact = await ethers.getContractFactory(
    "DerivativeFactory"
  );
  const deriFactoryContract = await deriFactoryArtifact.deploy();
  deriFactory = await deriFactoryContract.deployed();
  console.log("Derivative Factory Deployed at:", deriFactory.address);
}

async function deployTributaryFactory() {
  console.log("Starting Tributary Factory Deployment");
  const tribFactoryArtifact = await ethers.getContractFactory(
    "TributaryFactory"
  );
  const tribFactoryContract = await tribFactoryArtifact.deploy();
  tribFactory = await tribFactoryContract.deployed();
  console.log("Tributary Factory Deployed at:", tribFactory.address);
}

async function printDeployment() {
  console.log("**************************************************************");
  console.log("Derivative Factory: ", deriFactory.address);
  console.log("Tributary Factory: ", tribFactory.address);
  console.log("**************************************************************");
}

async function verifyDerivativeFactory() {
  console.log("Starting Derivative Factory Verification");
  await hre.run("verify:verify", {
    address: deriFactory.address,
    contract: "contracts/DerivativeFactory.sol:DerivativeFactory",
  });
  console.log("Derivative Factory Verified");
}

async function verifyTributaryFactory() {
  console.log("Starting Tributary Factory Verification");
  await hre.run("verify:verify", {
    address: tribFactory.address,
    contract: "contracts/TributaryFactory.sol:TributaryFactory",
  });
  console.log("Tributary Factory Verified");
}

async function main() {
  const [wallet] = await ethers.getSigners();
  console.log("Using wallet: ", wallet.address);

  await getContracts();

  //===================================================================
  // 1. Deploy System
  //===================================================================

  // console.log("Starting System Deployment");
  // await deployDerivativeFactory();
  // await deployTributaryFactory();
  // await printDeployment();

  /*********** UPDATE getContracts() with new addresses *************/

  //===================================================================
  // 2. Verify System
  //===================================================================

  // console.log("Starting Verification");
  // await verifyDerivativeFactory();
  // await verifyTributaryFactory();

  //===================================================================
  // 4. Transactions
  //===================================================================

  // console.log("Starting Transactions");
  // console.log("Transaction Sent");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

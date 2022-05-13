import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

describe('Setters', function () {
	let owner: SignerWithAddress;
	let brax: Contract;
	let BRAXFactory: ContractFactory;
	let governanceTimelock: string;

	const name: string = 'Brax';
	const symbol: string = 'BRAX';
	const randomAddress = '0x853d955aCEf822Db058eb8505911ED77F175b99e';
	const wbtc = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599';
	const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

	beforeEach(async function () {
		[owner] = await ethers.getSigners();
		governanceTimelock = '0xB65cef03b9B89f99517643226d76e286ee999e77';

		BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
		brax = await BRAXFactory.deploy(name, symbol, owner.address, governanceTimelock);
		await brax.deployed();
	});

	it('Should allow the correct address to set the redemption fee', async function () {
		const currentRedemptionFee = await brax.redemptionFee();
		const redFee = await brax.setRedemptionFee(5000);
		await redFee.wait();
		const newRedemptionFee = await brax.redemptionFee();

		expect(currentRedemptionFee).to.not.equal(newRedemptionFee);
		expect(newRedemptionFee).to.be.equal(5000);
	});

	it('Should allow the correct address to set the minting fee', async function () {
		const currentMintingFee = await brax.mintingFee();
		const mintFee = await brax.setMintingFee(5000);
		await mintFee.wait();
		const newMintingFee = await brax.mintingFee();

		expect(currentMintingFee).to.not.equal(newMintingFee);
		expect(newMintingFee).to.be.equal(5000);
	});

	it('Should allow the correct address to set the step', async function () {
		const currentStep = await brax.braxStep();
		const step = await brax.setBraxStep(5000);
		await step.wait();
		const newStep = await brax.braxStep();

		expect(currentStep).to.not.equal(newStep);
		expect(newStep).to.be.equal(5000);
	});

	it('Should allow the correct address to set the price target', async function () {
		const currentPriceTarget = await brax.priceTarget();
		const pt = await brax.setPriceTarget(5000);
		await pt.wait();
		const newPriceTarget = await brax.priceTarget();

		expect(currentPriceTarget).to.not.equal(newPriceTarget);
		expect(newPriceTarget).to.be.equal(5000);
	});

	it('Should allow the correct address to set the refresh cooldown', async function () {
		const currentRefresh = await brax.refreshCooldown();
		const rc = await brax.setRefreshCooldown(5000);
		await rc.wait();
		const newRefresh = await brax.refreshCooldown();

		expect(currentRefresh).to.not.equal(newRefresh);
		expect(newRefresh).to.be.equal(5000);
	});

	it('Should allow the correct address to set the BXS address', async function () {
		const currentBxs = await brax.bxsAddress();
		const bxs = await brax.setBXSAddress(randomAddress);
		await bxs.wait();
		const newBxs = await brax.bxsAddress();

		expect(currentBxs).to.not.equal(newBxs);
		expect(newBxs).to.be.equal(randomAddress);
	});

	it('Should not allow the zero address to be set for BXS', async function () {
		await expect(brax.setBXSAddress(ZERO_ADDRESS)).to.be.revertedWith('Zero address detected');
	});

	// Gotcha - the wbtc/btc oracle needs to be wrapped in the price consumer aggregator
	it('Should allow the correct address to set the wBTC:BTC Oracle', async function () {
		const OracleFactory = await ethers.getContractFactory('ChainlinkWBTCBTCPriceConsumer');
		const deployedOracle = await OracleFactory.deploy('0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23');
		await deployedOracle.deployed();

		const currentOracle = await brax.wbtcBtcConsumerAddress();
		const oracle = await brax.setWBTCBTCOracle(deployedOracle.address);
		await oracle.wait();
		const newOracle = await brax.wbtcBtcConsumerAddress();

		expect(currentOracle).to.not.equal(newOracle);
		expect(newOracle).to.be.equal(deployedOracle.address);
	});

	it('Should not allow the zero address to be set for the wBTC:BTC Oracle', async function () {
		await expect(brax.setWBTCBTCOracle(ZERO_ADDRESS)).to.be.revertedWith('Zero address detected');
	});

	it('Should allow the correct address to set the timelock address', async function () {
		const currentTimelock = await brax.timelockAddress();
		const timelock = await brax.setTimelock(wbtc);
		await timelock.wait();
		const newTimelock = await brax.timelockAddress();

		expect(currentTimelock).to.not.equal(newTimelock);
		expect(newTimelock).to.be.equal(wbtc);
	});

	it('Should not allow the zero address to be set for the timelock address', async function () {
		await expect(brax.setTimelock(ZERO_ADDRESS)).to.be.revertedWith('Zero address detected');
	});

	it('Should allow the correct address to set the controller address', async function () {
		const currentController = await brax.controllerAddress();
		const controller = await brax.setController(wbtc);
		await controller.wait();
		const newController = await brax.controllerAddress();

		expect(currentController).to.not.equal(newController);
		expect(newController).to.be.equal(wbtc);
	});

	it('Should not allow the zero address to be set for the controller address', async function () {
		await expect(brax.setController(ZERO_ADDRESS)).to.be.revertedWith('Zero address detected');
	});

	it('Should allow the correct address to set the price band', async function () {
		const currentPriceBand = await brax.priceBand();
		const pb = await brax.setPriceBand(5000);
		await pb.wait();
		const newPriceBand = await brax.priceBand();

		expect(currentPriceBand).to.not.equal(newPriceBand);
		expect(newPriceBand).to.be.equal(5000);
	});

	it('Should allow the correct address to set the BRAX wBTC Oracle', async function () {
		const currentOracle = await brax.braxWbtcOracleAddress();
		const oracle = await brax.setBRAXWBtcOracle(randomAddress, wbtc);
		await oracle.wait();
		const newOracle = await brax.braxWbtcOracleAddress();

		expect(currentOracle).to.not.equal(newOracle);
		expect(newOracle).to.be.equal(randomAddress);
	});

	it('Should not allow the zero address to be set for the BRAX wBTC Oracle', async function () {
		await expect(brax.setBRAXWBtcOracle(ZERO_ADDRESS, wbtc)).to.be.revertedWith('Zero address detected');
	});

	it('Should allow the correct address to set the BXS wBTC Oracle', async function () {
		const currentOracle = await brax.bxsWbtcOracleAddress();
		const oracle = await brax.setBXSWBtcOracle(randomAddress, wbtc);
		await oracle.wait();
		const newOracle = await brax.bxsWbtcOracleAddress();

		expect(currentOracle).to.not.equal(newOracle);
		expect(newOracle).to.be.equal(randomAddress);
	});

	it('Should not allow the zero address to be set for the BXS wBTC Oracle', async function () {
		await expect(brax.setBXSWBtcOracle(ZERO_ADDRESS, wbtc)).to.be.revertedWith('Zero address detected');
	});

	it('Should allow the correct address to toggle the collateral ratio', async function () {
		const currentCrStatus = await brax.collateralRatioPaused();
		const status = await brax.toggleCollateralRatio();
		await status.wait();
		const newCrStatus = await brax.collateralRatioPaused();

		expect(currentCrStatus).to.not.equal(newCrStatus);
		expect(newCrStatus).to.be.true;
	});

	it('Should not allow non-permissioned actors to perform permissioned functions', async function () {
		const [_, badActor] = await ethers.getSigners();

		// onlyByOwnerGovernanceOrController
		await expect(brax.connect(badActor).setRedemptionFee(5000)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setMintingFee(5000)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setBraxStep(5000)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setPriceTarget(5000)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setRefreshCooldown(5000)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setBXSAddress(randomAddress)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setWBTCBTCOracle(randomAddress)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setTimelock(randomAddress)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setController(randomAddress)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setPriceBand(5000)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setBRAXWBtcOracle(randomAddress, wbtc)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setBXSWBtcOracle(randomAddress, wbtc)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);

		// onlyCollateralRatioPauser
		await expect(brax.connect(badActor).toggleCollateralRatio()).to.be.revertedWith('!pauser');
	});
});

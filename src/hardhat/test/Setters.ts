import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

describe('Setters', function () {
	let owner: SignerWithAddress;
	let brax: Contract;
	let BRAXFactory: ContractFactory;
	let governance_timelock: string;

	const name: string = 'Brax';
	const symbol: string = 'BRAX';
	const random_address = '0x853d955aCEf822Db058eb8505911ED77F175b99e';
	const wbtc = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599';
	const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

	beforeEach(async function () {
		[owner] = await ethers.getSigners();
		governance_timelock = '0xB65cef03b9B89f99517643226d76e286ee999e77';

		BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
		brax = await BRAXFactory.deploy(name, symbol, owner.address, governance_timelock);
		await brax.deployed();
	});

	it('Should allow the correct address to set the redemption fee', async function () {
		const current_redemption_fee = await brax.redemption_fee();
		const red_fee = await brax.setRedemptionFee(5000);
		await red_fee.wait();
		const new_redemption_fee = await brax.redemption_fee();

		expect(current_redemption_fee).to.not.equal(new_redemption_fee);
		expect(new_redemption_fee).to.be.equal(5000);
	});

	it('Should allow the correct address to set the minting fee', async function () {
		const current_minting_fee = await brax.minting_fee();
		const mint_fee = await brax.setMintingFee(5000);
		await mint_fee.wait();
		const new_minting_fee = await brax.minting_fee();

		expect(current_minting_fee).to.not.equal(new_minting_fee);
		expect(new_minting_fee).to.be.equal(5000);
	});

	it('Should allow the correct address to set the step', async function () {
		const current_step = await brax.brax_step();
		const step = await brax.setBraxStep(5000);
		await step.wait();
		const new_step = await brax.brax_step();

		expect(current_step).to.not.equal(new_step);
		expect(new_step).to.be.equal(5000);
	});

	it('Should allow the correct address to set the price target', async function () {
		const current_price_target = await brax.price_target();
		const pt = await brax.setPriceTarget(5000);
		await pt.wait();
		const new_price_target = await brax.price_target();

		expect(current_price_target).to.not.equal(new_price_target);
		expect(new_price_target).to.be.equal(5000);
	});

	it('Should allow the correct address to set the refresh cooldown', async function () {
		const current_refresh = await brax.refresh_cooldown();
		const rc = await brax.setRefreshCooldown(5000);
		await rc.wait();
		const new_refresh = await brax.refresh_cooldown();

		expect(current_refresh).to.not.equal(new_refresh);
		expect(new_refresh).to.be.equal(5000);
	});

	it('Should allow the correct address to set the BXS address', async function () {
		const current_bxs = await brax.bxs_address();
		const bxs = await brax.setBXSAddress(random_address);
		await bxs.wait();
		const new_bxs = await brax.bxs_address();

		expect(current_bxs).to.not.equal(new_bxs);
		expect(new_bxs).to.be.equal(random_address);
	});

	// Gotcha - the wbtc/btc oracle needs to be wrapped in the price consumer aggregator
	it('Should allow the correct address to set the wBTC:BTC Oracle', async function () {
		const OracleFactory = await ethers.getContractFactory('ChainlinkWBTCBTCPriceConsumer');
		const deployed_oracle = await OracleFactory.deploy('0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23');
		await deployed_oracle.deployed();

		const current_oracle = await brax.wbtc_btc_consumer_address();
		const oracle = await brax.setWBTCBTCOracle(deployed_oracle.address);
		await oracle.wait();
		const new_oracle = await brax.wbtc_btc_consumer_address();

		expect(current_oracle).to.not.equal(new_oracle);
		expect(new_oracle).to.be.equal(deployed_oracle.address);
	});

	it('Should allow the correct address to set the timelock address', async function () {
		const current_timelock = await brax.timelock_address();
		const timelock = await brax.setTimelock(wbtc);
		await timelock.wait();
		const new_timelock = await brax.timelock_address();

		expect(current_timelock).to.not.equal(new_timelock);
		expect(new_timelock).to.be.equal(wbtc);
	});

	it('Should allow the correct address to set the controller address', async function () {
		const current_controller = await brax.controller_address();
		const controller = await brax.setController(wbtc);
		await controller.wait();
		const new_controller = await brax.controller_address();

		expect(current_controller).to.not.equal(new_controller);
		expect(new_controller).to.be.equal(wbtc);
	});

	it('Should allow the correct address to set the price band', async function () {
		const current_price_band = await brax.price_band();
		const pb = await brax.setPriceBand(5000);
		await pb.wait();
		const new_price_band = await brax.price_band();

		expect(current_price_band).to.not.equal(new_price_band);
		expect(new_price_band).to.be.equal(5000);
	});

	it('Should allow the correct address to set the BRAX wBTC Oracle', async function () {
		const current_oracle = await brax.brax_wbtc_oracle_address();
		const oracle = await brax.setBRAXWBtcOracle(random_address, wbtc);
		await oracle.wait();
		const new_oracle = await brax.brax_wbtc_oracle_address();

		expect(current_oracle).to.not.equal(new_oracle);
		expect(new_oracle).to.be.equal(random_address);
	});

	it('Should allow the correct address to set the BXS wBTC Oracle', async function () {
		const current_oracle = await brax.bxs_wbtc_oracle_address();
		const oracle = await brax.setBXSWBtcOracle(random_address, wbtc);
		await oracle.wait();
		const new_oracle = await brax.bxs_wbtc_oracle_address();

		expect(current_oracle).to.not.equal(new_oracle);
		expect(new_oracle).to.be.equal(random_address);
	});

	it('Should allow the correct address to toggle the collateral ratio', async function () {
		const current_cr_status = await brax.collateral_ratio_paused();
		const status = await brax.toggleCollateralRatio();
		await status.wait();
		const new_cr_status = await brax.collateral_ratio_paused();

		expect(current_cr_status).to.not.equal(new_cr_status);
		expect(new_cr_status).to.be.true;
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
		await expect(brax.connect(badActor).setBXSAddress(random_address)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setWBTCBTCOracle(random_address)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setTimelock(random_address)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setPriceBand(5000)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setBRAXWBtcOracle(random_address, wbtc)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
		await expect(brax.connect(badActor).setBXSWBtcOracle(random_address, wbtc)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);

		// onlyCollateralRatioPauser
		await expect(brax.connect(badActor).toggleCollateralRatio()).to.be.revertedWith('!pauser');
	});
});

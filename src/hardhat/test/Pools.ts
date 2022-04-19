import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers, network } from 'hardhat';
import ERC20 from '../abis/ERC20.json';

describe('Pools', function () {
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

	it('Should allow a permissioned address to add and remove a pool', async function () {
		const PoolFactory = await ethers.getContractFactory('BraxPoolV3');
		const deployed_pool = await PoolFactory.deploy(
			owner.address,
			owner.address,
			owner.address,
			[wbtc],
			['2100000000000000'],
			[3000, 5000, 4500, 4500],
			brax.address,
			random_address,
		);
		await deployed_pool.deployed();

		await expect(brax.brax_pools_array(0)).to.be.reverted;

		const add_pool = await brax.addPool(deployed_pool.address);
		await add_pool.wait();

		const new_pool = await brax.brax_pools_array(0);
		expect(new_pool).to.be.equal(deployed_pool.address);

		const remove_pool = await brax.removePool(deployed_pool.address);
		await remove_pool.wait();
		const removed_pool = await brax.brax_pools_array(0);
		expect(removed_pool).to.be.equal(ZERO_ADDRESS);
	});

	it('Should allow a pool to mint BRAX', async function () {
		// Deploy BXS
		const BXSFactory = await ethers.getContractFactory('BRAXShares');
		const BXS = await BXSFactory.deploy('BRAX Shares', 'BXS', random_address, owner.address, owner.address);
		await BXS.deployed();

		// Deploy Poolv3
		const PoolFactory = await ethers.getContractFactory('BraxPoolV3');
		const deployed_pool = await PoolFactory.deploy(
			owner.address,
			owner.address,
			owner.address,
			[wbtc],
			['2100000000000000'],
			[0, 0, 0, 0],
			brax.address,
			BXS.address,
		);
		await deployed_pool.deployed();

		const wbtcContract = new ethers.Contract(wbtc, ERC20.abi);

		await expect(brax.brax_pools_array(0)).to.be.reverted;

		const add_pool = await brax.addPool(deployed_pool.address);
		await add_pool.wait();

		const new_pool = await brax.brax_pools_array(0);
		expect(new_pool).to.be.equal(deployed_pool.address);

		// Enable wBTC collateral
		const enableWbtc = await deployed_pool.toggleCollateral(0);
		await enableWbtc.wait();

		// Impersonate an address with wBTC to test mint
		const wbtcWhaleAccount = '0xB60C61DBb7456f024f9338c739B02Be68e3F545C';
		await network.provider.request({
			method: 'hardhat_impersonateAccount',
			params: [wbtcWhaleAccount],
		});
		const wbtcWhale = await ethers.getSigner(wbtcWhaleAccount);

		// Set approval for pool to spend wBTC
		const approvePoolwBtc = await wbtcContract.connect(wbtcWhale).approve(deployed_pool.address, '100000000');
		await approvePoolwBtc.wait();

		// We need to modify the thresholds to prevent the transcation from reverting
		const pt = await deployed_pool.setPriceThresholds(0, 10000000000);
		await pt.wait();

		// Record wBTC balance of account
		const beforewBtcBalance = await wbtcContract.connect(owner).balanceOf(wbtcWhaleAccount);
		const beforeBalance = await brax.balanceOf(wbtcWhaleAccount);
		const mintBrax = await deployed_pool
			.connect(wbtcWhale)
			.mintBrax(0, '1000000000000000000', '990000000000000000', '100000000', 0, false);
		await mintBrax.wait();

		const afterMintBalance = await brax.balanceOf(wbtcWhaleAccount);
		const afterMintwBtcBalance = await wbtcContract.connect(owner).balanceOf(wbtcWhaleAccount);

		expect(parseInt(afterMintBalance)).to.be.equal(parseInt(beforeBalance.add('1000000000000000000')));
		expect(parseInt(afterMintwBtcBalance)).to.be.equal(parseInt(beforewBtcBalance.sub('100000000')));

		// Set approval for pool to spend BRAX
		const approvePool = await brax.connect(wbtcWhale).approve(deployed_pool.address, '100000000');
		await approvePool.wait();

		const burnBrax = await deployed_pool.connect(wbtcWhale).redeemBrax(0, '1000000', 0, 0);
		await burnBrax.wait();
		const afterBurnBalance = await brax.balanceOf(wbtcWhaleAccount);

		expect(parseInt(afterBurnBalance)).to.be.equal(parseInt(afterMintBalance.sub('1000000')));
	});

	it("Shouldn't allow non-pools to perform pool only actions", async function () {
		const [_, badActor] = await ethers.getSigners();

		await expect(brax.connect(badActor).pool_mint(badActor.address, '100000')).to.be.revertedWith(
			'Only brax pools can call this function',
		);
		await expect(brax.connect(badActor).pool_burn_from(random_address, '100000')).to.be.revertedWith(
			'Only brax pools can call this function',
		);
	});
});

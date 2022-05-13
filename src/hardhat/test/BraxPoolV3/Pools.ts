import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers, network } from 'hardhat';
import ERC20 from '../../abis/ERC20.json';

describe('Pools', function () {
	let owner: SignerWithAddress;
	let brax: Contract;
	let BRAXFactory: ContractFactory;
	let governanceTimelock: string;
	let startBlock: number;

	const name: string = 'Brax';
	const symbol: string = 'BRAX';
	const randomAddress = '0x853d955aCEf822Db058eb8505911ED77F175b99e';
	const wbtc = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599';
	const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

	beforeEach(async function () {
		[owner] = await ethers.getSigners();
		governanceTimelock = '0xB65cef03b9B89f99517643226d76e286ee999e77';
		startBlock = await ethers.provider.getBlockNumber();

		BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
		brax = await BRAXFactory.deploy(name, symbol, owner.address, governanceTimelock);
		await brax.deployed();
	});

	it('Should allow a permissioned address to add and remove a pool', async function () {
		const PoolFactory = await ethers.getContractFactory('BraxPoolV3');
		const deployedPool = await PoolFactory.deploy(
			owner.address,
			owner.address,
			owner.address,
			[wbtc],
			['2100000000000000'],
			[3000, 5000, 4500, 4500],
			brax.address,
			randomAddress,
		);
		await deployedPool.deployed();

		await expect(brax.braxPoolsArray(0)).to.be.reverted;

		const addPool = await brax.addPool(deployedPool.address);
		await addPool.wait();

		const newPool = await brax.braxPoolsArray(0);
		expect(newPool).to.be.equal(deployedPool.address);
		const newPoolMapping = await brax.braxPools(deployedPool.address);
		expect(newPoolMapping).to.be.equal(true);

		const removePool = await brax.removePool(deployedPool.address);
		await removePool.wait();
		const removedPool = await brax.braxPoolsArray(0);
		expect(removedPool).to.be.equal(ZERO_ADDRESS);
		const removedPoolMapping = await brax.braxPools(deployedPool.address);
		expect(removedPoolMapping).to.be.equal(false);
	});

	it('Should prevent you from adding the same pool twice', async function () {
		const PoolFactory = await ethers.getContractFactory('BraxPoolV3');
		const deployedPool = await PoolFactory.deploy(
			owner.address,
			owner.address,
			owner.address,
			[wbtc],
			['2100000000000000'],
			[3000, 5000, 4500, 4500],
			brax.address,
			randomAddress,
		);
		await deployedPool.deployed();

		await expect(brax.braxPoolsArray(0)).to.be.reverted;

		const addPool = await brax.addPool(deployedPool.address);
		await addPool.wait();

		await expect(brax.addPool(deployedPool.address)).to.be.revertedWith('Address already exists');
	});

	it('Should prevent you from removing a pool that does not exist', async function () {
		await expect(brax.removePool(randomAddress)).to.be.revertedWith('Address nonexistant');
	});

	it('Should not allow a non-address to be added or removed', async function () {
		try {
			const poolAdd = await brax.addPool('0xabc');
			await poolAdd.wait();
			throw new Error('Did not revert');
		} catch (err) {
			expect(err.message).to.include('invalid address');
		}

		try {
			const poolAdd = await brax.removePool('0xabc');
			await poolAdd.wait();
			throw new Error('Did not revert');
		} catch (err) {
			expect(err.message).to.include('invalid address');
		}
	});

	it('Should prevent unauthorized addresses from adding and removing pools', async function () {
		const PoolFactory = await ethers.getContractFactory('BraxPoolV3');
		const deployedPool = await PoolFactory.deploy(
			owner.address,
			owner.address,
			owner.address,
			[wbtc],
			['2100000000000000'],
			[3000, 5000, 4500, 4500],
			brax.address,
			randomAddress,
		);
		await deployedPool.deployed();

		const [_, badActor] = await ethers.getSigners();
		await expect(brax.connect(badActor).addPool(deployedPool.address)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);

		const addPool = await brax.addPool(deployedPool.address);
		await addPool.wait();

		await expect(brax.connect(badActor).removePool(deployedPool.address)).to.be.revertedWith(
			'Not the owner, controller, or the governance timelock',
		);
	});

	it('Should prevent a 0 address from being added or removed', async function () {
		await expect(brax.addPool(ZERO_ADDRESS)).to.be.revertedWith('Zero address detected');
		await expect(brax.removePool(ZERO_ADDRESS)).to.be.revertedWith('Zero address detected');
	});

	it('Should allow a pool to mint BRAX', async function () {
		// Deploy BXS
		const BXSFactory = await ethers.getContractFactory('BRAXShares');
		const BXS = await BXSFactory.deploy('BRAX Shares', 'BXS', randomAddress, owner.address, owner.address);
		await BXS.deployed();

		// Deploy Poolv3
		const PoolFactory = await ethers.getContractFactory('BraxPoolV3');
		const deployedPool = await PoolFactory.deploy(
			owner.address,
			owner.address,
			owner.address,
			[wbtc],
			['2100000000000000'],
			[0, 0, 0, 0],
			brax.address,
			BXS.address,
		);
		await deployedPool.deployed();

		const wbtcContract = new ethers.Contract(wbtc, ERC20.abi);

		await expect(brax.braxPoolsArray(0)).to.be.reverted;

		const addPool = await brax.addPool(deployedPool.address);
		await addPool.wait();

		const newPool = await brax.braxPoolsArray(0);
		expect(newPool).to.be.equal(deployedPool.address);

		// Enable wBTC collateral
		const enableWbtc = await deployedPool.toggleCollateral(0);
		await enableWbtc.wait();

		// Impersonate an address with wBTC to test mint
		const wbtcWhaleAccount = '0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0';
		await network.provider.request({
			method: 'hardhat_impersonateAccount',
			params: [wbtcWhaleAccount],
		});
		const wbtcWhale = await ethers.getSigner(wbtcWhaleAccount);

		// Set approval for pool to spend wBTC
		const approvePoolwBtc = await wbtcContract.connect(wbtcWhale).approve(deployedPool.address, '100000000');
		await approvePoolwBtc.wait();

		// We need to modify the thresholds to prevent the transcation from reverting
		// This is due to mocking the oracle and no reliable price coming through
		const pt = await deployedPool.setPriceThresholds(0, 10000000000);
		await pt.wait();

		// Record wBTC balance of account
		const beforewBtcBalance = await wbtcContract.connect(owner).balanceOf(wbtcWhaleAccount);
		const beforeBalance = await brax.balanceOf(wbtcWhaleAccount);
		const mintBrax = await deployedPool
			.connect(wbtcWhale)
			.mintBrax(0, '1000000000000000000', '990000000000000000', '100000000', 0, false);
		await mintBrax.wait();

		const afterMintBalance = await brax.balanceOf(wbtcWhaleAccount);
		const afterMintwBtcBalance = await wbtcContract.connect(owner).balanceOf(wbtcWhaleAccount);

		expect(parseInt(afterMintBalance)).to.be.equal(parseInt(beforeBalance.add('1000000000000000000')));
		expect(parseInt(afterMintwBtcBalance)).to.be.equal(parseInt(beforewBtcBalance.sub('100000000')));

		// Set approval for pool to spend BRAX
		const approvePool = await brax.connect(wbtcWhale).approve(deployedPool.address, '100000000');
		await approvePool.wait();

		const burnBrax = await deployedPool.connect(wbtcWhale).redeemBrax(0, '1000000', 0, 0);
		await burnBrax.wait();
		const afterBurnBalance = await brax.balanceOf(wbtcWhaleAccount);

		expect(parseInt(afterBurnBalance)).to.be.equal(parseInt(afterMintBalance.sub('1000000')));
	});

	it('Should prevent non-pools from performing pool only actions', async function () {
		const [_, badActor] = await ethers.getSigners();

		await expect(brax.connect(badActor).poolMint(badActor.address, '100000')).to.be.revertedWith(
			'Only brax pools can call this function',
		);
		await expect(brax.connect(badActor).poolBurnFrom(randomAddress, '100000')).to.be.revertedWith(
			'Only brax pools can call this function',
		);
	});
});

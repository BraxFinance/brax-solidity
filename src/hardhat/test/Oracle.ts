import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers, network } from 'hardhat';
import ERC20 from '../abis/ERC20.json';
import IUniswapV2Pair from '@uniswap/v2-core/build/IUniswapV2Pair.json';

describe('Oracle', function () {
	let owner: SignerWithAddress;
	let brax: Contract;
	let bxs: Contract;
	let BRAXFactory: ContractFactory;
	let BXSFactory: ContractFactory;
	let governance_timelock: string;

	const braxName: string = 'Brax';
	const braxSymbol: string = 'BRAX';
	const bxsName: string = 'Brax Shares';
	const bxsSymbol: string = 'BXS';

	const random_address = '0x853d955aCEf822Db058eb8505911ED77F175b99e';
	const wbtc = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599';
	const SECOND = 1000;

	let pair: any;
	let pairAddress: string;
	let router: Contract;
	let uniswapFactory: Contract;
	let weth: Contract;

	beforeEach(async function () {
		[owner] = await ethers.getSigners();
		governance_timelock = '0xB65cef03b9B89f99517643226d76e286ee999e77';

		BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
		brax = await BRAXFactory.deploy(braxName, braxSymbol, owner.address, governance_timelock);
		await brax.deployed();

		BXSFactory = await ethers.getContractFactory('BRAXShares');
		bxs = await BXSFactory.deploy(bxsName, bxsSymbol, random_address, owner.address, governance_timelock);
		await bxs.deployed();

		const compiledUniswapFactory = require('@uniswap/v2-core/build/UniswapV2Factory.json');
		uniswapFactory = await new ethers.ContractFactory(
			compiledUniswapFactory.interface,
			compiledUniswapFactory.bytecode,
			owner,
		).deploy(await owner.getAddress());
		await uniswapFactory.deployed();

		pair = await uniswapFactory.callStatic.createPair(brax.address, wbtc);

		const Weth = await ethers.getContractFactory('WETH9');
		weth = await Weth.deploy();

		const compiledUniswapRouter = require('@uniswap/v2-periphery/build/UniswapV2Router02');
		router = await new ethers.ContractFactory(
			compiledUniswapRouter.abi,
			compiledUniswapRouter.bytecode,
			owner,
		).deploy(uniswapFactory.address, weth.address);
	});

	// Create a pair on uniswap
	// Add liquidity to pair (wbtc/frax)
	// Create oracle using pair
	// Consult oracle
	it('Creates an oracle', async function () {
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
			bxs.address,
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

		// Impersonate an address with wBTC to mint
		const wbtcWhaleAccount = '0xB60C61DBb7456f024f9338c739B02Be68e3F545C';
		await network.provider.request({
			method: 'hardhat_impersonateAccount',
			params: [wbtcWhaleAccount],
		});
		const wbtcWhale = await ethers.getSigner(wbtcWhaleAccount);

		// Set approval for pool to spend wBTC
		const approvePoolwBtc = await wbtcContract.connect(wbtcWhale).approve(deployed_pool.address, '1000000000');
		await approvePoolwBtc.wait();

		// We need to modify the thresholds to prevent the transcation from reverting
		// This is due to mocking the oracle and no reliable price coming through
		const pt = await deployed_pool.setPriceThresholds(0, 10000000000);
		await pt.wait();

		const mintBrax = await deployed_pool
			.connect(wbtcWhale)
			.mintBrax(0, '10000000000000000000', '9900000000000000000', '1000000000', 0, false);
		await mintBrax.wait();

		// Deposit equal amounts of wBTC and BRAX to pool
		const approveRouterwBtc = await wbtcContract.connect(wbtcWhale).approve(router.address, '1000000000');
		await approveRouterwBtc.wait();

		const approveRouterBrax = await brax.connect(wbtcWhale).approve(router.address, '10000000000000000000');
		await approveRouterBrax.wait();

		const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
		const deposit = await router
			.connect(wbtcWhale)
			.addLiquidity(
				brax.address,
				wbtcContract.address,
				'10000000000000000000',
				'1000000000',
				'10000000000000000000',
				'1000000000',
				wbtcWhale.address,
				expiry,
			);
		await deposit.wait();

		// Create oracle
		const uniOracleFactory = await ethers.getContractFactory('UniswapPairOracle');
		const uniOracle = await uniOracleFactory.deploy(
			uniswapFactory.address,
			wbtcContract.address,
			brax.address,
			owner.address,
			owner.address,
		);

		await network.provider.send('evm_increaseTime', [3800]);
		await network.provider.send('evm_mine');

		const update = await uniOracle.update();
		await update.wait();

		// Check price of oracle
		const wbtcConsult = await uniOracle.consult(wbtcContract.address, ethers.utils.parseUnits('1', 8));
		const braxConsult = await uniOracle.consult(brax.address, ethers.utils.parseUnits('1', 18));
		// Reset time for the network
		await network.provider.send('evm_increaseTime', [-3800]);
		await network.provider.send('evm_mine');

		expect(wbtcConsult).to.be.closeTo(ethers.utils.parseUnits('1', 18), '1');
		expect(braxConsult).to.be.closeTo(ethers.utils.parseUnits('1', 8), '1');
	});
});

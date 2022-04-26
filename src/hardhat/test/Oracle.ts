import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers, network } from 'hardhat';
import ERC20 from '../abis/ERC20.json';
import IUniswapV2Router02 from '@uniswap/v2-periphery/build/IUniswapV2Router02.json';

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
	let wbtcWhale: SignerWithAddress;
	let wbtcWhaleAccount: string;

	const router = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';
	const uniswapFactory = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
	let weth: Contract;
	let startBlock: number;

	const wbtcContract = new ethers.Contract(wbtc, ERC20.abi);
	const routerContract = new ethers.Contract(router, IUniswapV2Router02.abi);

	beforeEach(async function () {
		[owner] = await ethers.getSigners();
		startBlock = await ethers.provider.getBlockNumber();
		governance_timelock = '0xB65cef03b9B89f99517643226d76e286ee999e77';
		// Impersonate an address with wBTC to mint
		wbtcWhaleAccount = '0xB60C61DBb7456f024f9338c739B02Be68e3F545C';
		await network.provider.request({
			method: 'hardhat_impersonateAccount',
			params: [wbtcWhaleAccount],
		});
		wbtcWhale = await ethers.getSigner(wbtcWhaleAccount);

		BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
		brax = await BRAXFactory.deploy(braxName, braxSymbol, owner.address, governance_timelock);
		await brax.deployed();

		BXSFactory = await ethers.getContractFactory('BRAXShares');
		bxs = await BXSFactory.deploy(bxsName, bxsSymbol, random_address, owner.address, governance_timelock);
		await bxs.deployed();

		const Weth = await ethers.getContractFactory('WETH9');
		weth = await Weth.deploy();

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

		await expect(brax.brax_pools_array(0)).to.be.reverted;

		const add_pool = await brax.addPool(deployed_pool.address);
		await add_pool.wait();

		const new_pool = await brax.brax_pools_array(0);
		expect(new_pool).to.be.equal(deployed_pool.address);

		// Enable wBTC collateral
		const enableWbtc = await deployed_pool.toggleCollateral(0);
		await enableWbtc.wait();

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
		const approveRouterwBtc = await wbtcContract.connect(wbtcWhale).approve(router, '1000000000');
		await approveRouterwBtc.wait();

		const approveRouterBrax = await brax.connect(wbtcWhale).approve(router, '10000000000000000000');
		await approveRouterBrax.wait();

		const expiry = 100000000000000;
		const deposit = await routerContract
			.connect(wbtcWhale)
			.addLiquidity(
				wbtcContract.address,
				brax.address,
				'1000000000',
				'10000000000000000000',
				'1000000000',
				'10000000000000000000',
				wbtcWhale.address,
				expiry,
			);
		await deposit.wait();

		// Transfer BXS and deposit to pool
		const bxsTransfer = await bxs.connect(owner).transfer(wbtcWhale.address, '100000000000000000000');
		await bxsTransfer.wait();

		const approveRouterwBtc2 = await wbtcContract.connect(wbtcWhale).approve(router, '1000000000');
		await approveRouterwBtc2.wait();

		const approveRouterBxs = await bxs.connect(wbtcWhale).approve(router, '100000000000000000000');
		await approveRouterBxs.wait();

		const depositBxs = await routerContract
			.connect(wbtcWhale)
			.addLiquidity(
				wbtcContract.address,
				bxs.address,
				'1000000000',
				'100000000000000000000',
				'1000000000',
				'100000000000000000000',
				wbtcWhale.address,
				expiry,
			);
		await depositBxs.wait();
	});

	it('Creates an oracle', async function () {
		// Create oracle
		const uniOracleFactory = await ethers.getContractFactory('UniswapPairOracle');
		const uniOracle = await uniOracleFactory.deploy(
			uniswapFactory,
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

		expect(wbtcConsult).to.be.closeTo(ethers.utils.parseUnits('1', 18), '1');
		expect(braxConsult).to.be.closeTo(ethers.utils.parseUnits('1', 8), '1');

		// Perform a swap, fast forward the chain then check consult again to ensure it was updated.
		const approveRouterwBtcSwap = await wbtcContract.connect(wbtcWhale).approve(router, '100000000');
		await approveRouterwBtcSwap.wait();
		const swapDeadline = 100000000000000;

		const swap = await routerContract
			.connect(wbtcWhale)
			.swapExactTokensForTokens('100000000', '0', [wbtc, brax.address], wbtcWhaleAccount, swapDeadline);
		await swap.wait();

		await network.provider.send('evm_increaseTime', [3800]);
		await network.provider.send('evm_mine');

		const updateAfterSwap = await uniOracle.update();
		await updateAfterSwap.wait();

		const wbtcConsultAfterSwap: number = parseInt(
			(await uniOracle.consult(wbtcContract.address, ethers.utils.parseUnits('1', 8))).toString(),
		);
		const braxConsultAfterSwap: number = parseInt(
			(await uniOracle.consult(brax.address, ethers.utils.parseUnits('1', 18))).toString(),
		);

		// Reset time for the network
		await network.provider.request({
			method: 'hardhat_reset',
			params: [
				{
					forking: {
						jsonRpcUrl: process.env.ETH_URL,
						blockNumber: startBlock,
					},
				},
			],
		});

		expect(wbtcConsultAfterSwap).to.be.lessThan(parseInt(ethers.utils.parseUnits('1', 18).toString()));
		expect(braxConsultAfterSwap).to.be.greaterThan(parseInt(ethers.utils.parseUnits('1', 8).toString()));
	});

	it('Assigns an oracle to BRAX', async function () {
		const uniOracleFactory = await ethers.getContractFactory('UniswapPairOracle');
		const uniOracle = await uniOracleFactory.deploy(
			uniswapFactory,
			wbtcContract.address,
			brax.address,
			owner.address,
			owner.address,
		);

		const OracleFactory = await ethers.getContractFactory('ChainlinkWBTCBTCPriceConsumer');
		const deployed_oracle = await OracleFactory.deploy('0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23');
		await deployed_oracle.deployed();

		const clOracle = await brax.setWBTCBTCOracle(deployed_oracle.address);
		await clOracle.wait();

		await network.provider.send('evm_increaseTime', [3800]);
		await network.provider.send('evm_mine');

		const update = await uniOracle.update();
		await update.wait();

		const assignOracle = await brax.setBRAXWBtcOracle(uniOracle.address, wbtc);
		await assignOracle.wait();

		const braxPrice = await brax.brax_price();
		const wBtcOraclePrice = await deployed_oracle.getLatestPrice();
		expect(braxPrice).to.be.closeTo(wBtcOraclePrice, '1');

		await network.provider.request({
			method: 'hardhat_reset',
			params: [
				{
					forking: {
						jsonRpcUrl: process.env.ETH_URL,
						blockNumber: startBlock,
					},
				},
			],
		});
	});

	it('Assigns an oracle to BXS', async function () {
		const uniOracleFactory = await ethers.getContractFactory('UniswapPairOracle');
		const uniOracle = await uniOracleFactory.deploy(
			uniswapFactory,
			wbtcContract.address,
			bxs.address,
			owner.address,
			owner.address,
		);

		const OracleFactory = await ethers.getContractFactory('ChainlinkWBTCBTCPriceConsumer');
		const deployed_oracle = await OracleFactory.deploy('0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23');
		await deployed_oracle.deployed();

		const clOracle = await brax.setWBTCBTCOracle(deployed_oracle.address);
		await clOracle.wait();

		await network.provider.send('evm_increaseTime', [3800]);
		await network.provider.send('evm_mine');

		const update = await uniOracle.update();
		await update.wait();

		const assignOracle = await brax.setBXSWBtcOracle(uniOracle.address, wbtc);
		await assignOracle.wait();

		const bxsPrice = await brax.bxs_price();
		const wBtcOraclePrice = await deployed_oracle.getLatestPrice();
		expect(bxsPrice).to.be.closeTo(BigNumber.from(parseInt(wBtcOraclePrice) / 10), '1');

		await network.provider.request({
			method: 'hardhat_reset',
			params: [
				{
					forking: {
						jsonRpcUrl: process.env.ETH_URL,
						blockNumber: startBlock,
					},
				},
			],
		});
	});
});

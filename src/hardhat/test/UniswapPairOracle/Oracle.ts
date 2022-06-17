import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers, network } from 'hardhat';
import ERC20 from '../../abis/ERC20.json';
import IUniswapV2Router02 from '@uniswap/v2-periphery/build/IUniswapV2Router02.json';

const router = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';
const uniswapFactory = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
const randomAddress = '0x853d955aCEf822Db058eb8505911ED77F175b99e';
const wbtc = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599';

const braxName: string = 'Brax';
const braxSymbol: string = 'BRAX';
const bxsName: string = 'Brax Shares';
const bxsSymbol: string = 'BXS';

const deployOracle = async (
	isBrax: boolean,
	contract: Contract,
	owner: SignerWithAddress,
	brax: Contract,
): Promise<Contract> => {
	const uniOracleFactory = await ethers.getContractFactory('UniswapPairOracle');
	const uniOracle = await uniOracleFactory.deploy(
		uniswapFactory,
		wbtc,
		contract.address,
		owner.address,
		owner.address,
	);

	await network.provider.send('evm_increaseTime', [3800]);
	await network.provider.send('evm_mine');

	const update = await uniOracle.update();
	await update.wait();

	if (isBrax) {
		const assignOracle = await brax.setBRAXWBtcOracle(uniOracle.address, wbtc);
		await assignOracle.wait();
	} else {
		const assignOracle = await brax.setBXSWBtcOracle(uniOracle.address, wbtc);
		await assignOracle.wait();
	}

	return uniOracle;
};

const swapTokens = async (
	fromToken: Contract,
	toToken: Contract,
	fromAccount: SignerWithAddress,
	routerContract: Contract,
	oracle: Contract,
	amount: string,
) => {
	const approveRouterwBtcSwap = await fromToken.connect(fromAccount).approve(router, amount);
	await approveRouterwBtcSwap.wait();

	const swapDeadline = 100000000000000;
	const swap = await routerContract
		.connect(fromAccount)
		.swapExactTokensForTokens(amount, '0', [fromToken.address, toToken.address], fromAccount.address, swapDeadline);
	await swap.wait();

	await network.provider.send('evm_increaseTime', [3800]);
	await network.provider.send('evm_mine');

	const updateAfterSwap = await oracle.update();
	await updateAfterSwap.wait();
};

describe('Oracle', function () {
	let owner: SignerWithAddress;
	let brax: Contract;
	let bxs: Contract;
	let BRAXFactory: ContractFactory;
	let BXSFactory: ContractFactory;
	let governanceTimelock: string;
	let wbtcOracle: Contract;
	let deployedPool: Contract;

	let wbtcWhale: SignerWithAddress;
	let wbtcWhaleAccount: string;

	let startBlock: number;

	const wbtcContract = new ethers.Contract(wbtc, ERC20.abi);
	const routerContract = new ethers.Contract(router, IUniswapV2Router02.abi);

	beforeEach(async function () {
		[owner] = await ethers.getSigners();
		startBlock = await ethers.provider.getBlockNumber();
		governanceTimelock = '0xB65cef03b9B89f99517643226d76e286ee999e77';

		// Impersonate an address with wBTC to mint
		// If this address no longer has funds, check etherscan to get an
		// address with sufficient funds to impersonate locally
		wbtcWhaleAccount = '0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0';
		await network.provider.request({
			method: 'hardhat_impersonateAccount',
			params: [wbtcWhaleAccount],
		});
		wbtcWhale = await ethers.getSigner(wbtcWhaleAccount);

		// Deploy BRAX, BXS and a pool to create a local version of BRAX
		BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
		brax = await BRAXFactory.deploy(braxName, braxSymbol, owner.address, governanceTimelock);
		await brax.deployed();

		BXSFactory = await ethers.getContractFactory('BRAXShares');
		bxs = await BXSFactory.deploy(bxsName, bxsSymbol, randomAddress, owner.address, governanceTimelock);
		await bxs.deployed();

		const PoolFactory = await ethers.getContractFactory('BraxPoolV3');
		deployedPool = await PoolFactory.deploy(
			owner.address,
			owner.address,
			owner.address,
			[wbtc],
			['2100000000000000'],
			[0, 0, 0, 0],
			brax.address,
			bxs.address,
		);
		await deployedPool.deployed();

		await expect(brax.braxPoolsArray(0)).to.be.reverted;

		const addPool = await brax.addPool(deployedPool.address);
		await addPool.wait();

		const newPool = await brax.braxPoolsArray(0);
		expect(newPool).to.be.equal(deployedPool.address);

		// Enable wBTC collateral and set oracle
		const enableWbtc = await deployedPool.toggleCollateral(0);
		await enableWbtc.wait();

		const OracleFactory = await ethers.getContractFactory('ChainlinkPriceConsumer');
		wbtcOracle = await OracleFactory.deploy('0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23');
		await wbtcOracle.deployed();

		const clOracle = await brax.setWBTCBTCOracle(wbtcOracle.address);
		await clOracle.wait();

		// We need to modify the thresholds to prevent the transcation from reverting
		// This is due to mocking the oracle and no reliable price coming through
		const pt = await deployedPool.setPriceThresholds(0, 10000000000);
		await pt.wait();

		// Set approval for pool to spend wBTC
		const approvePoolwBtc = await wbtcContract.connect(wbtcWhale).approve(deployedPool.address, '1000000000');
		await approvePoolwBtc.wait();

		const mintBrax = await deployedPool
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

	it('Creates an oracle and updates after swap', async function () {
		// We deploy an oracle and consult it.  Then we perform swaps
		// and make sure the oracle updates as expected

		const uniOracle = await deployOracle(true, brax, owner, brax);

		// Check price of oracle
		const wbtcConsult = await uniOracle.consult(wbtcContract.address, ethers.utils.parseUnits('1', 8));
		const braxConsult = await uniOracle.consult(brax.address, ethers.utils.parseUnits('1', 18));

		expect(wbtcConsult).to.be.closeTo(ethers.utils.parseUnits('1', 18), '1');
		expect(braxConsult).to.be.closeTo(ethers.utils.parseUnits('1', 8), '1');

		await swapTokens(wbtcContract, brax, wbtcWhale, routerContract, uniOracle, '100000000');

		const wbtcConsultAfterSwap: number = parseInt(
			(await uniOracle.consult(wbtcContract.address, ethers.utils.parseUnits('1', 8))).toString(),
		);
		const braxConsultAfterSwap: number = parseInt(
			(await uniOracle.consult(brax.address, ethers.utils.parseUnits('1', 18))).toString(),
		);

		expect(wbtcConsultAfterSwap).to.be.lessThan(parseInt(ethers.utils.parseUnits('1', 18).toString()));
		expect(braxConsultAfterSwap).to.be.greaterThan(parseInt(ethers.utils.parseUnits('1', 8).toString()));
	});

	it('Assigns an oracle to BRAX', async function () {
		await deployOracle(true, brax, owner, brax);

		const braxPrice = await brax.braxPrice();
		const wBtcOraclePrice = await wbtcOracle.getLatestPrice();
		expect(braxPrice).to.be.closeTo(wBtcOraclePrice, '1');
	});

	it('Assigns an oracle to BXS', async function () {
		await deployOracle(false, bxs, owner, brax);

		const bxsPrice = await brax.bxsPrice();
		const wBtcOraclePrice = await wbtcOracle.getLatestPrice();
		expect(bxsPrice).to.be.closeTo(BigNumber.from(wBtcOraclePrice.div(10)), '1');
	});

	it('Returns a stale error if price has not been updated in an hour', async function () {
		await deployOracle(true, brax, owner, brax);
		await network.provider.send('evm_increaseTime', [3800]);
		await network.provider.send('evm_mine');

		await expect(brax.braxPrice()).to.be.reverted;
	});

	it('Correctly returns Brax Info', async function () {
		const braxOracle = await deployOracle(true, brax, owner, brax);
		const bxsOracle = await deployOracle(false, bxs, owner, brax);

		await network.provider.send('evm_increaseTime', [3800]);
		await network.provider.send('evm_mine');

		const braxOracleUpdate = await braxOracle.update();
		const bxsOracleUpdate = await bxsOracle.update();
		await braxOracleUpdate.wait();
		await bxsOracleUpdate.wait();

		const braxInfo = await brax.braxInfo();
		expect(braxInfo.length).to.equal(7);
	});

	it('Correctly returns the global collateral ratio', async function () {
		// We check the GCR is set properly, then swap to make price > priceTarget + priceBand
		// This makes the GCR modifiable via refreshCollateralRatio
		// We then swap back to have the price within the price band and confirm that refreshCollateralRatio
		// cannot be called.  Finally, we swap again to make price < priceTarget - priceBand to increase
		// the collateral ratio

		const braxOracle = await deployOracle(true, brax, owner, brax);

		const gcr = await brax.globalCollateralRatio();
		expect(gcr).to.equal(1e8);

		// Move price above price target and refresh
		await swapTokens(wbtcContract, brax, wbtcWhale, routerContract, braxOracle, '10000000');

		const refresh = await brax.refreshCollateralRatio();
		await refresh.wait();

		const gcrAfterSwap = await brax.globalCollateralRatio();
		expect(gcrAfterSwap).to.be.equal(BigNumber.from('100000000').sub('250000'));

		const braxBalance = (await brax.balanceOf(wbtcWhaleAccount)).toString();

		// Move price back to within price target and attempt refresh
		await swapTokens(brax, wbtcContract, wbtcWhale, routerContract, braxOracle, braxBalance);

		const refresh2 = await brax.refreshCollateralRatio();
		await refresh2.wait();

		const gcrAfterSwap2 = await brax.globalCollateralRatio();
		expect(gcrAfterSwap2).to.be.equal(BigNumber.from('100000000').sub('250000'));

		// Move price below price target and refresh
		await swapTokens(brax, wbtcContract, owner, routerContract, braxOracle, braxBalance);

		const refresh3 = await brax.refreshCollateralRatio();
		await refresh3.wait();

		const gcrAfterSwap3 = await brax.globalCollateralRatio();
		expect(gcrAfterSwap3).to.be.equal(BigNumber.from('100000000'));

		await expect(brax.refreshCollateralRatio()).to.be.revertedWith(
			'Must wait for the refresh cooldown since last refresh',
		);
	});

	it('Should not allow you to move above MAX_COLLATERAL_RATIO', async function () {
		const braxOracle = await deployOracle(true, brax, owner, brax);

		const gcr = await brax.globalCollateralRatio();
		expect(gcr).to.equal(1e8);

		const maxCollateralRatio = await brax.MAX_COLLATERAL_RATIO();
		expect(gcr).to.equal(maxCollateralRatio);

		const swapAmount = '1000000000000000000';
		// Move price below price target and try to raise CR
		await swapTokens(brax, wbtcContract, owner, routerContract, braxOracle, swapAmount);

		const gcrAfterSwap = await brax.globalCollateralRatio();
		expect(gcr).to.equal(gcrAfterSwap);
	});

	it('Should not allow you to move below 0 collateral ratio', async function () {
		const braxOracle = await deployOracle(true, brax, owner, brax);
		const newBraxStep = 100000000;

		const step = await brax.setBraxStep(newBraxStep);
		await step.wait();

		await swapTokens(wbtcContract, brax, wbtcWhale, routerContract, braxOracle, '10000000');

		const refresh = await brax.refreshCollateralRatio();
		await refresh.wait();

		const gcr = await brax.globalCollateralRatio();
		expect(gcr).to.be.equal('0');

		await network.provider.send('evm_increaseTime', [3800]);
		await network.provider.send('evm_mine');
		const braxOracleUpdate = await braxOracle.update();
		await braxOracleUpdate.wait();

		const refresh2 = await brax.refreshCollateralRatio();
		await refresh2.wait();
		const gcr2 = await brax.globalCollateralRatio();
		expect(gcr2).to.be.equal('0');
	});

	it('Correctly returns the global collateral value', async function () {
		// Check to see if the GCV is correct initially
		// Then we mint BRAX and see if it increases correctly
		// Finally, we redeem BRAX and see if it decreases correctly

		const gcv = await brax.globalCollateralValue();
		expect(gcv).to.equal('10000000000000000000');

		// Add more collateral and then recheck
		const approvePoolwBtc = await wbtcContract.connect(wbtcWhale).approve(deployedPool.address, '1000000000');
		await approvePoolwBtc.wait();

		const mintBrax = await deployedPool
			.connect(wbtcWhale)
			.mintBrax(0, '10000000000000000000', '9900000000000000000', '1000000000', 0, false);
		await mintBrax.wait();

		const gcv2 = await brax.globalCollateralValue();
		expect(gcv2).to.equal('20000000000000000000');

		const approvePool = await brax.connect(wbtcWhale).approve(deployedPool.address, '1000000000000000000');
		await approvePool.wait();

		const burnBrax = await deployedPool.connect(wbtcWhale).redeemBrax(0, '1000000000000000000', 0, 0);
		await burnBrax.wait();

		const gcv3 = await brax.globalCollateralValue();
		expect(gcv3).to.equal('19000000000000000000');
	});

	it('Should not allow you to refresh if paused', async function () {
		const status = await brax.toggleCollateralRatio();
		await status.wait();

		await expect(brax.refreshCollateralRatio()).to.be.revertedWith('Collateral Ratio has been paused');
	});
});

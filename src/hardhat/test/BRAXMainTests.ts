import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers, network } from 'hardhat';
import ERC20 from '../abis/ERC20.json';
import { getPermitSignature } from '../utils/EIP2612';

describe('BRAX', function () {
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

	describe('Deployment', function () {
		it('Should set the correct creator address', async function () {
			expect(await brax.creator_address()).to.equal(owner.address);
		});

		it('Should set the correct governance timelock address', async function () {
			expect(await brax.timelock_address()).to.equal(governance_timelock);
		});

		it('Should grant the correct roles to the creator', async function () {
			const admin_role = await brax.DEFAULT_ADMIN_ROLE();
			const collat_pauser = await brax.COLLATERAL_RATIO_PAUSER();
			const default_admin_address = await brax.DEFAULT_ADMIN_ADDRESS();

			expect(await brax.hasRole(admin_role, owner.address)).to.be.true;
			expect(await brax.getRoleMemberCount(admin_role)).to.equal(1);

			expect(await brax.hasRole(collat_pauser, owner.address)).to.be.true;
			expect(await brax.hasRole(collat_pauser, governance_timelock)).to.be.true;
			expect(await brax.getRoleMemberCount(collat_pauser)).to.equal(2);

			expect(default_admin_address).to.be.equal(owner.address);
		});

		it('Should return false for an account without a role', async function () {
			const admin_role = await brax.DEFAULT_ADMIN_ROLE();
			const collat_pauser = await brax.COLLATERAL_RATIO_PAUSER();

			expect(await brax.hasRole(admin_role, random_address)).to.be.false;
			expect(await brax.hasRole(collat_pauser, random_address)).to.be.false;
		});

		it('Should mint the correct amount to the correct address', async function () {
			const genesis_supply = await brax.genesis_supply();

			expect(await brax.balanceOf(owner.address)).to.be.equal(genesis_supply);
			expect(await brax.totalSupply()).to.be.equal(genesis_supply);
		});

		it('Should correctly name the identifiers', async function () {
			const contract_name = await brax.name();
			const contract_symbol = await brax.symbol();

			expect(contract_name).to.be.equal(name);
			expect(contract_symbol).to.be.equal(symbol);
		});
	});

	describe('Setters', function () {
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

	describe('Pools', function () {
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

	describe('ERC20Permit Testing', function () {
		it('Should return the correct PERMIT_TYPEHASH', async function () {
			const hash = await brax.PERMIT_TYPEHASH();
			expect(hash).to.be.equal('0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9');
		});

		it('Should increase allowance with a valid permit', async function () {
			const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
			const SECOND = 1000;
			const fromAddress = wallet.address;
			const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
			const spender = random_address;
			const value = '100000000';
			const config = {
				nonce: await brax.nonces(wallet.address),
				name: await brax.name(),
				chainId: 31337,
				version: '1',
			};
			const data = await getPermitSignature(wallet, brax, spender, value, expiry, undefined, config);
			const approvalAmount = await brax.allowance(fromAddress, spender);
			expect(approvalAmount).to.be.equal(0);
			const permit = await brax.permit(
				fromAddress,
				spender,
				value,
				expiry,
				data.typedData.v,
				data.typedData.r,
				data.typedData.s,
			);
			await permit.wait();
			const afterApprovalAmount = await brax.allowance(fromAddress, spender);
			expect(afterApprovalAmount).to.be.equal(value);
		});

		it('Should prevent replays on other chains', async function () {
			const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
			const SECOND = 1000;
			const fromAddress = wallet.address;
			const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
			const spender = random_address;
			const value = '100000000';
			const config = {
				nonce: await brax.nonces(wallet.address),
				name: await brax.name(),
				chainId: 1,
				version: '1',
			};
			const data = await getPermitSignature(wallet, brax, spender, value, expiry, undefined, config);
			const approvalAmount = await brax.allowance(fromAddress, spender);
			expect(approvalAmount).to.be.equal(0);
			await expect(
				brax.permit(fromAddress, spender, value, expiry, data.typedData.v, data.typedData.r, data.typedData.s),
			).to.be.revertedWith('BRAX: INVALID_SIGNATURE');
		});

		it('Should revert if signature is for non-owned account', async function () {
			const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
			const secondWallet = ethers.Wallet.createRandom().connect(
				ethers.getDefaultProvider('http://localhost:8545'),
			);
			const SECOND = 1000;
			const fromAddress = wallet.address;
			const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
			const spender = random_address;
			const value = '100000000';
			const config = {
				nonce: await brax.nonces(wallet.address),
				name: await brax.name(),
				chainId: 173872385,
				version: '1',
			};
			const data = await getPermitSignature(wallet, brax, spender, value, expiry, secondWallet.address, config);
			const approvalAmount = await brax.allowance(fromAddress, spender);
			expect(approvalAmount).to.be.equal(0);
			await expect(
				brax
					.connect(wallet)
					.permit(fromAddress, spender, value, expiry, data.typedData.v, data.typedData.r, data.typedData.s),
			).to.be.revertedWith('BRAX: INVALID_SIGNATURE');
		});

		it('Should revert if past deadline', async function () {});
	});
});

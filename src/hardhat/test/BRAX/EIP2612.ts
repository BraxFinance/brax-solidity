import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';
import { getPermitSignature } from '../../utils/EIP2612';

describe('ERC20Permit Testing', function () {
	let owner: SignerWithAddress;
	let brax: Contract;
	let BRAXFactory: ContractFactory;
	let governanceTimelock: string;

	const name: string = 'Brax';
	const symbol: string = 'BRAX';
	const randomAddress = '0x853d955aCEf822Db058eb8505911ED77F175b99e';

	beforeEach(async function () {
		[owner] = await ethers.getSigners();
		governanceTimelock = '0xB65cef03b9B89f99517643226d76e286ee999e77';

		BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
		brax = await BRAXFactory.deploy(name, symbol, owner.address, governanceTimelock);
		await brax.deployed();
	});

	it('Should return the correct PERMIT_TYPEHASH', async function () {
		const hash = await brax.PERMIT_TYPEHASH();
		expect(hash).to.be.equal('0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9');
	});

	it('Should increase allowance with a valid permit', async function () {
		const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const SECOND = 1000;
		const fromAddress = wallet.address;
		const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
		const spender = randomAddress;
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
		const spender = randomAddress;
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

	it('Should revert if V is incorrect', async function () {
		const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const SECOND = 1000;
		const fromAddress = wallet.address;
		const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
		const spender = randomAddress;
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
		await expect(
			brax.permit(fromAddress, spender, value, expiry, data.typedData.v + 1, data.typedData.r, data.typedData.s),
		).to.be.revertedWith('BRAX: INVALID_SIGNATURE');
	});

	it('Should revert if R is incorrect', async function () {
		const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const SECOND = 1000;
		const fromAddress = wallet.address;
		const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
		const spender = randomAddress;
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
		await expect(
			brax.permit(fromAddress, spender, value, expiry, data.typedData.v, data.typedData.s, data.typedData.s),
		).to.be.revertedWith('BRAX: INVALID_SIGNATURE');
	});

	it('Should revert if S is incorrect', async function () {
		const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const SECOND = 1000;
		const fromAddress = wallet.address;
		const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
		const spender = randomAddress;
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
		await expect(
			brax.permit(fromAddress, spender, value, expiry, data.typedData.v, data.typedData.r, data.typedData.r),
		).to.be.revertedWith('BRAX: INVALID_SIGNATURE');
	});

	it('Should revert if signature is for non-owned account', async function () {
		const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const secondWallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const SECOND = 1000;
		const fromAddress = wallet.address;
		const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
		const spender = randomAddress;
		const value = '100000000';
		const config = {
			nonce: await brax.nonces(wallet.address),
			name: await brax.name(),
			chainId: 31337,
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

	it('Should revert if signature is for less than the value requested', async function () {
		const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const SECOND = 1000;
		const fromAddress = wallet.address;
		const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
		const spender = randomAddress;
		const value = '100000000';
		const incorrectValue = '100000001';
		const config = {
			nonce: await brax.nonces(wallet.address),
			name: await brax.name(),
			chainId: 31337,
			version: '1',
		};
		const data = await getPermitSignature(wallet, brax, spender, value, expiry, undefined, config);
		const approvalAmount = await brax.allowance(fromAddress, spender);
		expect(approvalAmount).to.be.equal(0);
		await expect(
			brax.permit(
				fromAddress,
				spender,
				incorrectValue,
				expiry,
				data.typedData.v,
				data.typedData.r,
				data.typedData.s,
			),
		).to.be.revertedWith('BRAX: INVALID_SIGNATURE');
	});

	it('Should revert if spender is incorrect', async function () {
		const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const SECOND = 1000;
		const fromAddress = wallet.address;
		const expiry = BigNumber.from(Math.trunc((Date.now() + 120 * SECOND) / SECOND));
		const spender = randomAddress;
		const invalidSpender = wallet.address;
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
		await expect(
			brax.permit(
				fromAddress,
				invalidSpender,
				value,
				expiry,
				data.typedData.v,
				data.typedData.r,
				data.typedData.s,
			),
		).to.be.revertedWith('BRAX: INVALID_SIGNATURE');
	});

	it('Should revert if past deadline', async function () {
		const wallet = ethers.Wallet.createRandom().connect(ethers.getDefaultProvider('http://localhost:8545'));
		const SECOND = 1000;
		const fromAddress = wallet.address;
		const expiry = BigNumber.from(Math.trunc((Date.now() - 100000 * SECOND) / SECOND));
		const spender = randomAddress;
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
		await expect(
			brax.permit(fromAddress, spender, value, expiry, data.typedData.v, data.typedData.r, data.typedData.s),
		).to.be.revertedWith('BRAX: permit is expired');
	});
});

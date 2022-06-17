import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

describe('Deployment', function () {
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

	it('Should set the correct creator address', async function () {
		expect(await brax.creatorAddress()).to.equal(owner.address);
	});

	it('Should set the correct governance timelock address', async function () {
		expect(await brax.timelockAddress()).to.equal(governanceTimelock);
	});

	it('Should grant the correct roles to the creator', async function () {
		const adminRole = await brax.DEFAULT_ADMIN_ROLE();
		const collatPauser = await brax.COLLATERAL_RATIO_PAUSER();
		const defaultAdminAddress = await brax.DEFAULT_ADMIN_ADDRESS();

		expect(await brax.hasRole(adminRole, owner.address)).to.be.true;
		expect(await brax.getRoleMemberCount(adminRole)).to.equal(1);

		expect(await brax.hasRole(collatPauser, owner.address)).to.be.true;
		expect(await brax.hasRole(collatPauser, governanceTimelock)).to.be.true;
		expect(await brax.getRoleMemberCount(collatPauser)).to.equal(2);

		expect(defaultAdminAddress).to.be.equal(owner.address);
	});

	it('Should return false for an account without a role', async function () {
		const adminRole = await brax.DEFAULT_ADMIN_ROLE();
		const collatPauser = await brax.COLLATERAL_RATIO_PAUSER();

		expect(await brax.hasRole(adminRole, randomAddress)).to.be.false;
		expect(await brax.hasRole(collatPauser, randomAddress)).to.be.false;
	});

	it('Should mint the correct amount to the correct address', async function () {
		const genesisSupply = await brax.genesisSupply();

		expect(await brax.balanceOf(owner.address)).to.be.equal(genesisSupply);
		expect(await brax.totalSupply()).to.be.equal(genesisSupply);
	});

	it('Should correctly name the identifiers', async function () {
		const contractName = await brax.name();
		const contractSymbol = await brax.symbol();

		expect(contractName).to.be.equal(name);
		expect(contractSymbol).to.be.equal(symbol);
	});

	it('Should properly construct the DOMAIN_SEPARATOR', async function () {
		const hashedName = ethers.utils.solidityKeccak256(['bytes'], [ethers.utils.toUtf8Bytes(await brax.name())]);
		const hashedVersion = ethers.utils.solidityKeccak256(['bytes'], [ethers.utils.toUtf8Bytes('1')]);
		const typeHash = ethers.utils.solidityKeccak256(
			['bytes'],
			[
				ethers.utils.toUtf8Bytes(
					'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)',
				),
			],
		);
		const abiCoder = new ethers.utils.AbiCoder();
		const types = ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'];
		const values = [typeHash, hashedName, hashedVersion, 31337, brax.address];
		const expectedDomainSeparator = ethers.utils.solidityKeccak256(['bytes'], [abiCoder.encode(types, values)]);
		const domainSeparator = await brax.DOMAIN_SEPARATOR();
		expect(expectedDomainSeparator).to.be.equal(domainSeparator);
	});
});

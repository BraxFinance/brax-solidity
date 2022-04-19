import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

describe('Deployment', function () {
	let owner: SignerWithAddress;
	let brax: Contract;
	let BRAXFactory: ContractFactory;
	let governance_timelock: string;

	const name: string = 'Brax';
	const symbol: string = 'BRAX';
	const random_address = '0x853d955aCEf822Db058eb8505911ED77F175b99e';

	beforeEach(async function () {
		[owner] = await ethers.getSigners();
		governance_timelock = '0xB65cef03b9B89f99517643226d76e286ee999e77';

		BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
		brax = await BRAXFactory.deploy(name, symbol, owner.address, governance_timelock);
		await brax.deployed();
	});

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

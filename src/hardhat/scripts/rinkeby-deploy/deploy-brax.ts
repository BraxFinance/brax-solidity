import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';

async function main() {
	let owner: SignerWithAddress;
	let governanceTimelock: string;

	const name: string = 'Brax';
	const symbol: string = 'BRAX';

	[owner] = await ethers.getSigners();
	governanceTimelock = owner.address;

	const BRAXFactory = await ethers.getContractFactory('BRAXBtcSynth');
	const brax = await BRAXFactory.deploy(name, symbol, owner.address, governanceTimelock);
	await brax.deployed();

	console.log('======================================');
	console.log('Brax Deployed at address: ', brax.address);
	console.log('======================================');
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});

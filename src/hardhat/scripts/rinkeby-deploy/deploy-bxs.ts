import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';

async function main() {
	let owner: SignerWithAddress;

	const name: string = 'BraxShares';
	const symbol: string = 'BXS';

	[owner] = await ethers.getSigners();

	const BXSFactory = await ethers.getContractFactory('BRAXShares');
	const BXS = await BXSFactory.deploy(name, symbol, owner.address, owner.address, owner.address);
	const bxs = await BXS.deployed();
	console.log('======================================');
	console.log('BXS Deployed at address: ', bxs.address);
	console.log('======================================');
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});

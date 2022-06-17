import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';

async function main() {
	let owner: SignerWithAddress;

	[owner] = await ethers.getSigners();

	const PoolFactory = await ethers.getContractFactory('BraxPoolV3');
	const deployedPool = await PoolFactory.deploy(
		owner.address,
		owner.address,
		owner.address,
		['0x577D296678535e4903D59A4C929B718e1D575e0A'],
		['2100000000000000'],
		[3000, 5000, 4500, 4500],
		'0x50095eCf28C819E852415cc300E11aF3eaa08Bc7',
		'0x79d899b1DFd8F5A31f9c89be3832D6BDE73FEEBA',
		'0x5d160C4ab5bdac8650085FeCb3E1768843bbAc4D',
		'0x4aB6AF6a912e6d494541410781BE8c7313f6f601',
		'0x577D296678535e4903D59A4C929B718e1D575e0A',
	);

	await deployedPool.deployed();
	console.log('======================================');
	console.log('Brax Pool Deployed at address: ', deployedPool.address);
	console.log('======================================');
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});

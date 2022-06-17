// constructor (
//     address pair,
//     address _owner_address,
//     address _timelock_address
// )

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';

async function main() {
	let owner: SignerWithAddress;

	[owner] = await ethers.getSigners();

	const OracleFactory = await ethers.getContractFactory('UniswapPairOracle');
	const braxWbtcOracle = await OracleFactory.deploy(
		'0x0746a6bEdb1Aa39Cd6d758D55A4076003AaA0103',
		owner.address,
		owner.address,
	);
	const braxWbtc = await braxWbtcOracle.deployed();
	console.log('======================================');
	console.log('Brax / WBTC Oracle Deployed at address: ', braxWbtc.address);
	console.log('======================================');

	const bxsWbtcOracle = await OracleFactory.deploy(
		'0xba63539E1ec37dA9bD75bd4730DEFe1be46114c4',
		owner.address,
		owner.address,
	);
	const bxsWbtc = await bxsWbtcOracle.deployed();
	console.log('======================================');
	console.log('BXS / WBTC Oracle Deployed at address: ', bxsWbtc.address);
	console.log('======================================');
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});

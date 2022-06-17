import * as dotenv from 'dotenv';

import { HardhatUserConfig, task } from 'hardhat/config';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-vyper';

dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
	const accounts = await hre.ethers.getSigners();

	for (const account of accounts) {
		console.log(account.address);
	}
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
	vyper: {
		version: '0.3.1',
	},
	networks: {
		mainnet: {
			url: process.env.ETH_URL || '',
			accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
		},
		ropsten: {
			url: process.env.ROPSTEN_URL || '',
			accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
		},
		rinkeby: {
			url: process.env.RINKEBY_URL || '',
			accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
		},
		hardhat: {
			forking: {
				url: process.env.ETH_URL || '',
			},
		},
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_API_KEY,
	},
	solidity: {
		compilers: [
			{
				version: '0.4.18',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
			{
				version: '0.5.16',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
			{
				version: '0.5.17',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
			{
				version: '0.6.11',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
			{
				version: '0.6.12',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
			{
				version: '0.7.6',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
			// {
			// 	version: "0.8.0",
			// 	settings: {
			// 		optimizer: {
			// 			enabled: true,
			// 			runs: 100000
			// 		}
			// 	  }
			// },
			// {
			// 	version: "0.8.2",
			// 	settings: {
			// 		optimizer: {
			// 			enabled: true,
			// 			runs: 100000
			// 		}
			// 	  }
			// },
			{
				version: '0.8.4',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
			{
				version: '0.8.6',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
			{
				version: '0.8.10',
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000,
					},
				},
			},
		],
	},
};

export default config;

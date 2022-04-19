import { BigNumberish, constants, Signature, Wallet, Contract, BigNumber, ethers } from 'ethers';
import { splitSignature } from 'ethers/lib/utils';

export interface SignatureData {
	message: {
		owner: string;
		spender: string;
		value: BigNumberish;
		nonce: any;
		deadline: BigNumber;
	};
	typedData: Signature;
}

export async function getPermitSignature(
	wallet: Wallet,
	token: Contract,
	spender: string,
	value: BigNumberish = constants.MaxUint256,
	deadline = constants.MaxUint256,
	fakeOwner?: string,
	permitConfig?: { nonce?: BigNumberish; name?: string; chainId?: number; version?: string },
): Promise<SignatureData> {
	const [nonce, name, version, chainId] = await Promise.all([
		permitConfig?.nonce ?? token.nonces(wallet.address),
		permitConfig?.name ?? token.name(),
		permitConfig?.version ?? '1',
		permitConfig?.chainId ?? wallet.getChainId(),
	]);

	const message = {
		owner: fakeOwner ?? wallet.address,
		spender: spender,
		value: value,
		nonce: nonce,
		deadline: deadline,
	};

	const domain = {
		name: name,
		version: version,
		chainId: chainId,
		verifyingContract: token.address,
	};

	const types = {
		Permit: [
			{
				name: 'owner',
				type: 'address',
			},
			{
				name: 'spender',
				type: 'address',
			},
			{
				name: 'value',
				type: 'uint256',
			},
			{
				name: 'nonce',
				type: 'uint256',
			},
			{
				name: 'deadline',
				type: 'uint256',
			},
		],
	};

	const signature = await wallet._signTypedData(domain, types, message);

	const typedData = splitSignature(signature);

	const expectedSignerAddress = wallet.address;
	const recoveredAddress = ethers.utils.verifyTypedData(domain, types, message, signature);
	if (!fakeOwner && recoveredAddress !== expectedSignerAddress) {
		throw new Error('Error signing data, recovered address != expected address');
	}

	return { message, typedData };
}

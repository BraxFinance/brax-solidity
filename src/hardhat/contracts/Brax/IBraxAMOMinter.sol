// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.11;

// MAY need to be updated
interface IBraxAMOMinter {
  function BRAX() external view returns(address);
  function BXS() external view returns(address);
  function acceptOwnership() external;
  function addAMO(address amo_address, bool sync_too) external;
  function allAMOAddresses() external view returns(address[] memory);
  function allAMOsLength() external view returns(uint256);
  function amos(address) external view returns(bool);
  function amos_array(uint256) external view returns(address);
  function burnBraxFromAMO(uint256 frax_amount) external;
  function burnBxsFromAMO(uint256 fxs_amount) external;
  function col_idx() external view returns(uint256);
  function collatBtcBalance() external view returns(uint256);
  function collatBtcBalanceStored() external view returns(uint256);
  function collat_borrow_cap() external view returns(int256);
  function collat_borrowed_balances(address) external view returns(int256);
  function collat_borrowed_sum() external view returns(int256);
  function collateral_address() external view returns(address);
  function collateral_token() external view returns(address);
  function correction_offsets_amos(address, uint256) external view returns(int256);
  function custodian_address() external view returns(address);
  function btcBalances() external view returns(uint256 frax_val_e18, uint256 collat_val_e18);
  // function execute(address _to, uint256 _value, bytes _data) external returns(bool, bytes);
  function braxBtcBalanceStored() external view returns(uint256);
  function braxTrackedAMO(address amo_address) external view returns(int256);
  function braxTrackedGlobal() external view returns(int256);
  function brax_mint_balances(address) external view returns(int256);
  function brax_mint_cap() external view returns(int256);
  function brax_mint_sum() external view returns(int256);
  function bxs_mint_balances(address) external view returns(int256);
  function bxs_mint_cap() external view returns(int256);
  function bxs_mint_sum() external view returns(int256);
  function giveCollatToAMO(address destination_amo, uint256 collat_amount) external;
  function min_cr() external view returns(uint256);
  function mintBraxForAMO(address destination_amo, uint256 frax_amount) external;
  function mintBxsForAMO(address destination_amo, uint256 fxs_amount) external;
  function missing_decimals() external view returns(uint256);
  function nominateNewOwner(address _owner) external;
  function nominatedOwner() external view returns(address);
  function oldPoolCollectAndGive(address destination_amo) external;
  function oldPoolRedeem(uint256 frax_amount) external;
  function old_pool() external view returns(address);
  function owner() external view returns(address);
  function pool() external view returns(address);
  function receiveCollatFromAMO(uint256 usdc_amount) external;
  function recoverERC20(address tokenAddress, uint256 tokenAmount) external;
  function removeAMO(address amo_address, bool sync_too) external;
  function setAMOCorrectionOffsets(address amo_address, int256 frax_e18_correction, int256 collat_e18_correction) external;
  function setCollatBorrowCap(uint256 _collat_borrow_cap) external;
  function setCustodian(address _custodian_address) external;
  function setBraxMintCap(uint256 _frax_mint_cap) external;
  function setBraxPool(address _pool_address) external;
  function setBxsMintCap(uint256 _fxs_mint_cap) external;
  function setMinimumCollateralRatio(uint256 _min_cr) external;
  function setTimelock(address new_timelock) external;
  function syncBtcBalances() external;
  function timelock_address() external view returns(address);
}
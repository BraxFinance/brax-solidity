// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.11;

interface IBxs {
  function DEFAULT_ADMIN_ROLE() external view returns(bytes32);
  function BRAXBtcSynthAdd() external view returns(address);
  function BXS_DAO_MIN() external view returns(uint256);
  function allowance(address owner, address spender) external view returns(uint256);
  function approve(address spender, uint256 amount) external returns(bool);
  function balanceOf(address account) external view returns(uint256);
  function burn(uint256 amount) external;
  function burnFrom(address account, uint256 amount) external;
  function checkpoints(address, uint32) external view returns(uint32 fromBlock, uint96 votes);
  function decimals() external view returns(uint8);
  function decreaseAllowance(address spender, uint256 subtractedValue) external returns(bool);
  function genesisSupply() external view returns(uint256);
  function getCurrentVotes(address account) external view returns(uint96);
  function getPriorVotes(address account, uint256 blockNumber) external view returns(uint96);
  function getRoleAdmin(bytes32 role) external view returns(bytes32);
  function getRoleMember(bytes32 role, uint256 index) external view returns(address);
  function getRoleMemberCount(bytes32 role) external view returns(uint256);
  function grantRole(bytes32 role, address account) external;
  function hasRole(bytes32 role, address account) external view returns(bool);
  function increaseAllowance(address spender, uint256 addedValue) external returns(bool);
  function mint(address to, uint256 amount) external;
  function name() external view returns(string memory);
  function numCheckpoints(address) external view returns(uint32);
  function oracleAddress() external view returns(address);
  function ownerAddress() external view returns(address);
  function poolBurnFrom(address bAddress, uint256 bAmount) external;
  function poolMint(address mAddress, uint256 mAmount) external;
  function renounceRole(bytes32 role, address account) external;
  function revokeRole(bytes32 role, address account) external;
  function setBRAXAddress(address braxContractAddress) external;
  function setBXSMinDAO(uint256 minBXS) external;
  function setOracle(address newOracle) external;
  function setOwner(address _ownerAddress) external;
  function setTimelock(address newTimelock) external;
  function symbol() external view returns(string memory);
  function timelockAddress() external view returns(address);
  function toggleVotes() external;
  function totalSupply() external view returns(uint256);
  function trackingVotes() external view returns(bool);
  function transfer(address recipient, uint256 amount) external returns(bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns(bool);
}
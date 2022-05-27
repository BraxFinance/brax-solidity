# [🔗](/contracts/BXS/BXS.sol#L33) BRAXShares

# Data Structures

## [🔗](/contracts/BXS/BXS.sol#L53) Checkpoint

### Properties

-   `uint32 fromBlock`
-   `uint96 votes`

# Functions

## [🔗](/contracts/BXS/BXS.sol#L104) `setOracle(address newOracle)`

Sets the oracle address for BXS

### Parameters

-   `newOracle` Address of the new BXS oracle

## [🔗](/contracts/BXS/BXS.sol#L114) `setTimelock(address newTimelock)`

Set a new timelock address

### Parameters

-   `newTimelock` Address of the new timelock

## [🔗](/contracts/BXS/BXS.sol#L123) `setBRAXAddress(address braxContractAddress)`

Set the address of BRAX

### Parameters

-   `braxContractAddress` Address of BRAX

## [🔗](/contracts/BXS/BXS.sol#L135) `setBXSMinDAO(uint256 minBXS)`

Set the minimum amount of BXS required to join DAO

### Parameters

-   `minBXS` amount of BXS required to join DAO

## [🔗](/contracts/BXS/BXS.sol#L143) `mint(address to, uint256 amount)`

Mint new BXS

### Parameters

-   `to` Address to mint to
-   `amount` Amount to mint

## [🔗](/contracts/BXS/BXS.sol#L152) `poolMint(address mAddress, uint256 mAmount)`

Mint new BXS via pool

### Parameters

-   `mAddress` Address to mint to
-   `mAmount` Amount to mint

## [🔗](/contracts/BXS/BXS.sol#L170) `poolBurnFrom(address bAddress, uint256 bAmount)`

Burn BXS via pool

### Parameters

-   `bAddress` Address to burn from
-   `bAmount` Amount to burn

## [🔗](/contracts/BXS/BXS.sol#L188) `toggleVotes()`

Toggles tracking votes

## [🔗](/contracts/BXS/BXS.sol#L195) `transfer(address recipient, uint256 amount)`

Overwritten to track votes

### Parameters

-   `recipient`
-   `amount`

### Returns

-   `bool`

## [🔗](/contracts/BXS/BXS.sol#L206) `transferFrom(address sender, address recipient, uint256 amount)`

Overwritten to track votes

### Parameters

-   `sender`
-   `recipient`
-   `amount`

### Returns

-   `bool`

## [🔗](/contracts/BXS/BXS.sol#L221) `getCurrentVotes(address account)`

Gets the current votes balance for `account`

### Parameters

-   `account` The address to get votes balance

### Returns

-   `uint96`

## [🔗](/contracts/BXS/BXS.sol#L231) `getPriorVotes(address account, uint blockNumber)`

Block number must be a finalized block or else this function will revert to prevent misinformation.

Determine the prior number of votes for an account as of a block number

### Parameters

-   `account` The address of the account to check
-   `blockNumber` The block number to get the vote balance at

### Returns

-   `uint96`

## [🔗](/contracts/BXS/BXS.sol#L274) `trackVotes(address srcRep, address dstRep, uint96 amount)`

Keep track of votes. "Delegates" is a misnomer here

### Parameters

-   `srcRep`
-   `dstRep`
-   `amount`

## [🔗](/contracts/BXS/BXS.sol#L294) `_writeCheckpoint(address voter, uint32 nCheckpoints, uint96 oldVotes, uint96 newVotes)`

## [🔗](/contracts/BXS/BXS.sol#L307) `safe32(uint n, string errorMessage)`

## [🔗](/contracts/BXS/BXS.sol#L312) `safe96(uint n, string errorMessage)`

## [🔗](/contracts/BXS/BXS.sol#L317) `add96(uint96 a, uint96 b, string errorMessage)`

## [🔗](/contracts/BXS/BXS.sol#L323) `sub96(uint96 a, uint96 b, string errorMessage)`

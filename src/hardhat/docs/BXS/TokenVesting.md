# [🔗](/contracts/BXS/TokenVesting.sol#L8) TokenVesting

A token holder contract that can release its token balance gradually like a typical vesting scheme, with a cliff and vesting period. Optionally revocable by the owner.

Modified from OpenZeppelin's TokenVesting.sol draft

# Functions

## [🔗](/contracts/BXS/TokenVesting.sol#L80) `setBXSAddress(address BXSAddress)`

## [🔗](/contracts/BXS/TokenVesting.sol#L86) `setTimelockAddress(address timelockAddress)`

## [🔗](/contracts/BXS/TokenVesting.sol#L91) `getBeneficiary()`

### Returns

-   `address`

## [🔗](/contracts/BXS/TokenVesting.sol#L98) `getCliff()`

### Returns

-   `uint256`

## [🔗](/contracts/BXS/TokenVesting.sol#L105) `getStart()`

### Returns

-   `uint256`

## [🔗](/contracts/BXS/TokenVesting.sol#L112) `getDuration()`

### Returns

-   `uint256`

## [🔗](/contracts/BXS/TokenVesting.sol#L119) `getRevocable()`

### Returns

-   `bool`

## [🔗](/contracts/BXS/TokenVesting.sol#L126) `getReleased()`

### Returns

-   `uint256`

## [🔗](/contracts/BXS/TokenVesting.sol#L133) `getRevoked()`

### Returns

-   `bool`

## [🔗](/contracts/BXS/TokenVesting.sol#L140) `release()`

Transfers vested tokens to beneficiary.

## [🔗](/contracts/BXS/TokenVesting.sol#L156) `revoke()`

Allows the owner to revoke the vesting. Tokens already vested remain in the contract, the rest are returned to the owner.

## [🔗](/contracts/BXS/TokenVesting.sol#L178) `recoverERC20(address tokenAddress, uint256 tokenAmount)`

## [🔗](/contracts/BXS/TokenVesting.sol#L187) `_releasableAmount()`

Calculates the amount that has already vested but hasn't been released yet.

### Returns

-   `uint256`

## [🔗](/contracts/BXS/TokenVesting.sol#L194) `_vestedAmount()`

Calculates the amount that has already vested.

### Returns

-   `uint256`

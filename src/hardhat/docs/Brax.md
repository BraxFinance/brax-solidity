# [🔗](/contracts/Brax/Brax.sol#L39) BRAXBtcSynth

# Functions

## [🔗](/contracts/Brax/Brax.sol#L147) `oracle_price(PriceChoice choice)`

Retrieves oracle price for the provided PriceChoice enum

### Parameters

-   `choice` Token to return pricing information for

### Returns

-   `uint256` price X tokens required for 1 BTC

## [🔗](/contracts/Brax/Brax.sol#L169) `brax_price()`

### Returns

-   `uint256` price X BRAX = 1 BTC

## [🔗](/contracts/Brax/Brax.sol#L174) `bxs_price()`

### Returns

-   `uint256` price X BXS = 1 BTC

## [🔗](/contracts/Brax/Brax.sol#L179) `brax_info()`

It is cheaper gas-wise to just dump everything and only use some of the info

Return all info regarding BRAX

### Returns

-   `uint256` [ braxPrice - Oracle price of BRAX, bxsPrice - Oracle price of BXS, totalSupply - Total supply of BRAX, global_collateral_ratio - Current global collateral ratio of BRAX, globalCollateralValue - Current free value in the BRAX system, minting_fee Fee to mint BRAX, redemption_fee Fee to redeem BRAX ]
-   `uint256` [ braxPrice - Oracle price of BRAX, bxsPrice - Oracle price of BXS, totalSupply - Total supply of BRAX, global_collateral_ratio - Current global collateral ratio of BRAX, globalCollateralValue - Current free value in the BRAX system, minting_fee Fee to mint BRAX, redemption_fee Fee to redeem BRAX ]
-   `uint256` [ braxPrice - Oracle price of BRAX, bxsPrice - Oracle price of BXS, totalSupply - Total supply of BRAX, global_collateral_ratio - Current global collateral ratio of BRAX, globalCollateralValue - Current free value in the BRAX system, minting_fee Fee to mint BRAX, redemption_fee Fee to redeem BRAX ]
-   `uint256` [ braxPrice - Oracle price of BRAX, bxsPrice - Oracle price of BXS, totalSupply - Total supply of BRAX, global_collateral_ratio - Current global collateral ratio of BRAX, globalCollateralValue - Current free value in the BRAX system, minting_fee Fee to mint BRAX, redemption_fee Fee to redeem BRAX ]
-   `uint256` [ braxPrice - Oracle price of BRAX, bxsPrice - Oracle price of BXS, totalSupply - Total supply of BRAX, global_collateral_ratio - Current global collateral ratio of BRAX, globalCollateralValue - Current free value in the BRAX system, minting_fee Fee to mint BRAX, redemption_fee Fee to redeem BRAX ]
-   `uint256` [ braxPrice - Oracle price of BRAX, bxsPrice - Oracle price of BXS, totalSupply - Total supply of BRAX, global_collateral_ratio - Current global collateral ratio of BRAX, globalCollateralValue - Current free value in the BRAX system, minting_fee Fee to mint BRAX, redemption_fee Fee to redeem BRAX ]
-   `uint256` [ braxPrice - Oracle price of BRAX, bxsPrice - Oracle price of BXS, totalSupply - Total supply of BRAX, global_collateral_ratio - Current global collateral ratio of BRAX, globalCollateralValue - Current free value in the BRAX system, minting_fee Fee to mint BRAX, redemption_fee Fee to redeem BRAX ]

## [🔗](/contracts/Brax/Brax.sol#L205) `globalCollateralValue()`

Iterate through all brax pools and calculate all value of collateral in all pools globally denominated in BTC

### Returns

-   `uint256` balance Balance of all pools denominated in BTC (e18)

## [🔗](/contracts/Brax/Brax.sol#L228) `refreshCollateralRatio()`

## [🔗](/contracts/Brax/Brax.sol#L253) `permitNonces(address owner)`

Nonces for permit

### Parameters

-   `owner` Token owner's address (Authorizer)

### Returns

-   `uint256` next nonce

## [🔗](/contracts/Brax/Brax.sol#L262) `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`

Verify a signed approval permit and execute if valid

### Parameters

-   `owner` Token owner's address (Authorizer)
-   `spender` Spender's address
-   `value` Amount of allowance
-   `deadline` The time at which this expires (unix time)
-   `v` v of the signature
-   `r` r of the signature
-   `s` s of the signature

## [🔗](/contracts/Brax/Brax.sol#L309) `pool_burn_from(address b_address, uint256 b_amount)`

Burn BRAX as a step for releasing collateral

### Parameters

-   `b_address` address of user to burn from
-   `b_amount` amount of tokens to burn

## [🔗](/contracts/Brax/Brax.sol#L319) `pool_mint(address m_address, uint256 m_amount)`

Mint BRAX via pools after depositing collateral

### Parameters

-   `m_address` address of user to mint to
-   `m_amount` amount of tokens to mint

## [🔗](/contracts/Brax/Brax.sol#L329) `addPool(address pool_address)`

Add a new pool to be used for collateral, such as wBTC and renBTC, must be ERC20

### Parameters

-   `pool_address` address of pool to add

## [🔗](/contracts/Brax/Brax.sol#L343) `removePool(address pool_address)`

Remove a pool, leaving a 0x0 address in the index to retain the order of the other pools

### Parameters

-   `pool_address` address of pool to remove

## [🔗](/contracts/Brax/Brax.sol#L365) `setRedemptionFee(uint256 red_fee)`

Set fee for redemption of BRAX to collateral

### Parameters

-   `red_fee` fee in 8 decimal precision (e.g. 100000000 = 1% redemption fee)

## [🔗](/contracts/Brax/Brax.sol#L375) `setMintingFee(uint256 min_fee)`

Set fee for minting BRAX from collateral

### Parameters

-   `min_fee` fee in 8 decimal precision (e.g. 100000000 = 1% minting fee)

## [🔗](/contracts/Brax/Brax.sol#L385) `setBraxStep(uint256 _new_step)`

Set the step that the collateral rate can be changed by

### Parameters

-   `_new_step` step in 8 decimal precision (e.g. 250000 = 0.25%)

## [🔗](/contracts/Brax/Brax.sol#L395) `setPriceTarget(uint256 _new_price_target)`

Set the price target BRAX is aiming to stay at

### Parameters

-   `_new_price_target` price for BRAX to target in 8 decimals precision (e.g. 10000000 = 1 BTC)

## [🔗](/contracts/Brax/Brax.sol#L405) `setRefreshCooldown(uint256 _new_cooldown)`

Set the rate at which the collateral rate can be updated

### Parameters

-   `_new_cooldown` cooldown length in seconds (e.g. 3600 = 1 hour)

## [🔗](/contracts/Brax/Brax.sol#L415) `setBXSAddress(address _bxs_address)`

Set the address for BXS

### Parameters

-   `_bxs_address` new address for BXS

## [🔗](/contracts/Brax/Brax.sol#L427) `setWBTCBTCOracle(address _wbtc_btc_consumer_address)`

Set the wBTC / BTC Oracle

### Parameters

-   `_wbtc_btc_consumer_address` new address for the oracle

## [🔗](/contracts/Brax/Brax.sol#L441) `setTimelock(address new_timelock)`

Set the governance timelock address

### Parameters

-   `new_timelock` new address for the timelock

## [🔗](/contracts/Brax/Brax.sol#L453) `setController(address _controller_address)`

Set the controller address

### Parameters

-   `_controller_address` new address for the controller

## [🔗](/contracts/Brax/Brax.sol#L465) `setPriceBand(uint256 _price_band)`

Set the tolerance away from the target price in which the collateral rate cannot be updated

### Parameters

-   `_price_band` new tolerance with 8 decimals precision (e.g. 500000 will not adjust if between 0.995 BTC and 1.005 BTC)

## [🔗](/contracts/Brax/Brax.sol#L475) `setBRAXWBtcOracle(address _brax_oracle_addr, address _wbtc_address)`

Set the BRAX / wBTC Oracle

### Parameters

-   `_brax_oracle_addr` new address for the oracle
-   `_wbtc_address` undefined

## [🔗](/contracts/Brax/Brax.sol#L488) `setBXSWBtcOracle(address _bxs_oracle_addr, address _wbtc_address)`

Set the BXS / wBTC Oracle

### Parameters

-   `_bxs_oracle_addr` new address for the oracle
-   `_wbtc_address` undefined

## [🔗](/contracts/Brax/Brax.sol#L502) `toggleCollateralRatio()`

Toggle if the Collateral Ratio should be able to be updated

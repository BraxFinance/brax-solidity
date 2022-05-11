# [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L43) BraxPoolV3

# Data Structures

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L199) CollateralInformation

### Properties

-   `uint256 index`
-   `string symbol`
-   `address col_addr`
-   `bool is_enabled`
-   `uint256 missing_decs`
-   `uint256 price`
-   `uint256 pool_ceiling`
-   `bool mint_paused`
-   `bool redeem_paused`
-   `bool recollat_paused`
-   `bool buyback_paused`
-   `bool borrowing_paused`
-   `uint256 minting_fee`
-   `uint256 redemption_fee`
-   `uint256 buyback_fee`
-   `uint256 recollat_fee`

# Functions

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L220) `comboCalcBbkRct(uint256 cur, uint256 max, uint256 theo)`

helper function to help limit volatility in calculations

### Parameters

-   `cur`
-   `max`
-   `theo`

### Returns

-   `uint256`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L243) `collateral_information(address collat_address)`

Return the collateral information for a provided address

### Parameters

-   `collat_address` address of a type of collateral, e.g. wBTC or renBTC

### Returns

-   `CollateralInformation return_data` return_data struct containing all data regarding the provided collateral address

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L274) `allCollaterals()`

Returns a list of all collateral addresses

### Returns

-   `undefined addresses` addresses list of all collateral addresses

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L282) `getBRAXPrice()`

Return current price from chainlink feed for BRAX

### Returns

-   `uint256` price Current price of BRAX chainlink feed

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L293) `getBXSPrice()`

Return current price from chainlink feed for BXS

### Returns

-   `uint256` price Current price of BXS chainlink feed

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L304) `getBRAXInCollateral(uint256 col_idx, uint256 brax_amount)`

getting price for wBTC would be in 8 decimals

Return price of BRAX in the provided collateral token

### Parameters

-   `col_idx` index of collateral token (e.g. 0 for wBTC, 1 for renBTC)
-   `brax_amount` amount of BRAX to get the equivalent price for

### Returns

-   `uint256` price price of BRAX in collateral (decimals are equivalent to collateral, not BRAX)

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L316) `freeCollatBalance(uint256 col_idx)`

Return amount of collateral balance not waiting to be redeemed

### Parameters

-   `col_idx` index of collateral token (e.g. 0 for wBTC, 1 for renBTC)

### Returns

-   `uint256` amount amount of collateral not waiting to be redeemed (E18)

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L325) `collatBtcBalance()`

Returns BTC value of collateral held in this Brax pool, in E18

### Returns

-   `uint256 balance_tally` balance_tally total BTC value in pool (E18)

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L338) `buybackAvailableCollat()`

comboCalcBbkRct() is used to throttle buybacks to avoid dumps during periods of large volatility

Returns the value of excess collateral (E18) held globally, compared to what is needed to maintain the global collateral ratio

### Returns

-   `uint256` total excess collateral in the system (E18)

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L364) `recollatTheoColAvailableE18()`

Returns the missing amount of collateral (in E18) needed to maintain the collateral ratio

### Returns

-   `uint256` balance_tally total BTC value in pool in E18

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L383) `recollatAvailableBxs()`

utilizes comboCalcBbkRct to throttle for periods of high volatility

Returns the value of BXS available to be used for recollats

### Returns

-   `uint256` total value of BXS available for recollateralization

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L404) `curEpochHr()`

### Returns

-   `uint256` hour current epoch hour

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L411) `mintBrax(uint256 col_idx, uint256 brax_amt, uint256 brax_out_min, uint256 max_collat_in, uint256 max_bxs_in, bool one_to_one_override)`

Mint BRAX via collateral / BXS combination

### Parameters

-   `col_idx` integer value of the collateral index
-   `brax_amt` Amount of BRAX to mint
-   `brax_out_min` Minimum amount of BRAX to accept
-   `max_collat_in` Maximum amount of collateral to use for minting
-   `max_bxs_in` Maximum amount of BXS to use for minting
-   `one_to_one_override` Boolean flag to indicate using 1:1 BRAX:Collateral for
    minting, ignoring current global collateral ratio of BRAX

### Returns

-   `uint256 total_brax_mint` bxs_needed Amount of BXS used
-   `uint256 collat_needed` bxs_needed Amount of BXS used
-   `uint256 bxs_needed` bxs_needed Amount of BXS used

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L480) `redeemBrax(uint256 col_idx, uint256 brax_amount, uint256 bxs_out_min, uint256 col_out_min)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L541) `collectRedemption(uint256 col_idx)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L573) `buyBackFxs(uint256 col_idx, uint256 fxs_amount, uint256 col_out_min)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L608) `recollateralize(uint256 col_idx, uint256 collateral_amount, uint256 bxs_out_min)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L640) `amoMinterBorrow(uint256 collateral_amount)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L656) `toggleMRBR(uint256 col_idx, uint8 tog_idx)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L668) `addAMOMinter(address amo_minter_addr)`

Add an AMO Minter Address

### Parameters

-   `amo_minter_addr` Address of the new AMO minter

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L682) `removeAMOMinter(address amo_minter_addr)`

Remove an AMO Minter Address

### Parameters

-   `amo_minter_addr` Address of the AMO minter to remove

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L695) `setCollateralPrice(uint256 col_idx, uint256 _new_price)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L703) `toggleCollateral(uint256 col_idx)`

Toggles collateral for use in the pool

### Parameters

-   `col_idx` Index of the collateral to be enabled

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L714) `setPoolCeiling(uint256 col_idx, uint256 new_ceiling)`

Set the ceiling of collateral allowed for minting

### Parameters

-   `col_idx` Index of the collateral to be modified
-   `new_ceiling` New ceiling amount of collateral

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L725) `setFees(uint256 col_idx, uint256 new_mint_fee, uint256 new_redeem_fee, uint256 new_buyback_fee, uint256 new_recollat_fee)`

Set the fees of collateral allowed for minting

### Parameters

-   `col_idx` Index of the collateral to be modified
-   `new_mint_fee` New mint fee for collateral
-   `new_redeem_fee` New redemption fee for collateral
-   `new_buyback_fee` New buyback fee for collateral
-   `new_recollat_fee` New recollateralization fee for collateral

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L742) `setPoolParameters(uint256 new_bonus_rate, uint256 new_redemption_delay)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L748) `setPriceThresholds(uint256 new_mint_price_threshold, uint256 new_redeem_price_threshold)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L754) `setBbkRctPerHour(uint256 _bbkMaxColE18OutPerHour, uint256 _rctMaxFxsOutPerHour)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L761) `setOracles(address _brax_btc_chainlink_addr, address _bxs_btc_chainlink_addr)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L773) `setCustodian(address new_custodian)`

## [🔗](/contracts/Brax/Pools/BraxPoolV3.sol#L779) `setTimelock(address new_timelock)`

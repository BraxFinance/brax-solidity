// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;


                                                                

// ======================================================================
// |     ____  ____  ___   _  __    _______                             | 
// |    / __ )/ __ \/   | | |/ /   / ____(____  ____ _____  ________    | 
// |   / __  / /_/ / /| | |   /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / /_/ / _, _/ ___ |/   |   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_____/_/ |_/_/  |_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                    |
// ======================================================================
// ============================ BraxPoolV3 ==============================
// ======================================================================
// Allows multiple btc sythns (fixed amount at initialization) as collateral
// wBTC, ibBTC and renBTC to start
// For this pool, the goal is to accept decentralized assets as collateral to limit
// government / regulatory risk (e.g. wBTC blacklisting until holders KYC)

// Brax Finance: https://github.com/BraxFinance

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Jason Huan: https://github.com/jasonhuan
// Sam Kazemian: https://github.com/samkazemian
// Dennis: github.com/denett
// Hameed
// Andrew Mitchell: https://github.com/mitche50

import "../../Math/SafeMath.sol";
import '../../Uniswap/TransferHelper.sol';
import "../../Staking/Owned.sol";
import "../../BXS/IBxs.sol";
import "../../Brax/IBrax.sol";
import "../../Oracle/AggregatorV3Interface.sol";
import "../../Brax/IBraxAMOMinter.sol";
import "../../ERC20/ERC20.sol";

contract BraxPoolV3 is Owned {
    using SafeMath for uint256;
    // SafeMath automatically included in Solidity >= 8.0.0

    /* ========== STATE VARIABLES ========== */

    // Core
    address public timelock_address;
    address public custodian_address; // Custodian is an EOA (or msig) with pausing privileges only, in case of an emergency

    IBrax private BRAX;
    IBxs private BXS;

    mapping(address => bool) public amo_minter_addresses; // minter address -> is it enabled
    // TODO: Get aggregator
    // IMPORTANT - set to random chainlink contract for testing
    AggregatorV3Interface public priceFeedBRAXBTC = AggregatorV3Interface(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    // TODO: Get aggregator
    // IMPORTANT - set to random chainlink contract for testing
    AggregatorV3Interface public priceFeedBXSBTC = AggregatorV3Interface(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    uint256 private chainlink_brax_btc_decimals;
    uint256 private chainlink_bxs_btc_decimals;

    // Collateral
    address[] public collateral_addresses;
    string[] public collateral_symbols;
    uint256[] public missing_decimals; // Number of decimals needed to get to E18. collateral index -> missing_decimals
    uint256[] public pool_ceilings; // Total across all collaterals. Accounts for missing_decimals
    uint256[] public collateral_prices; // Stores price of the collateral, if price is paused.  Currently hardcoded at 1:1 BTC. CONSIDER ORACLES EVENTUALLY!!!
    mapping(address => uint256) public collateralAddrToIdx; // collateral addr -> collateral index
    mapping(address => bool) public enabled_collaterals; // collateral address -> is it enabled
    
    // Redeem related
    mapping (address => uint256) public redeemBXSBalances;
    mapping (address => mapping(uint256 => uint256)) public redeemCollateralBalances; // Address -> collateral index -> balance
    uint256[] public unclaimedPoolCollateral; // collateral index -> balance
    uint256 public unclaimedPoolBXS;
    mapping (address => uint256) public lastRedeemed; // Collateral independent
    uint256 public redemption_delay = 2; // Number of blocks to wait before being able to collectRedemption()
    uint256 public redeem_price_threshold = 99000000; // 0.99 BTC
    uint256 public mint_price_threshold = 101000000; // 1.01 BTC
    
    // Buyback related
    mapping(uint256 => uint256) public bbkHourlyCum; // Epoch hour ->  Collat out in that hour (E18)
    uint256 public bbkMaxColE18OutPerHour = 1e18;

    // Recollat related
    mapping(uint256 => uint256) public rctHourlyCum; // Epoch hour ->  FXS out in that hour
    uint256 public rctMaxFxsOutPerHour = 1000e18;

    // Fees and rates
    // getters are in collateral_information()
    uint256[] private minting_fee;
    uint256[] private redemption_fee;
    uint256[] private buyback_fee;
    uint256[] private recollat_fee;
    uint256 public bonus_rate; // Bonus rate on FXS minted during recollateralize(); 6 decimals of precision, set to 0.75% on genesis
    
    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e8;

    // Pause variables
    // getters are in collateral_information()
    bool[] private mintPaused; // Collateral-specific
    bool[] private redeemPaused; // Collateral-specific
    bool[] private recollateralizePaused; // Collateral-specific
    bool[] private buyBackPaused; // Collateral-specific
    bool[] private borrowingPaused; // Collateral-specific

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require(msg.sender == timelock_address || msg.sender == owner, "Not owner or timelock");
        _;
    }

    modifier onlyByOwnGovCust() {
        require(msg.sender == timelock_address || msg.sender == owner || msg.sender == custodian_address, "Not owner, tlck, or custd");
        _;
    }

    modifier onlyAMOMinters() {
        require(amo_minter_addresses[msg.sender], "Not an AMO Minter");
        _;
    }

    modifier collateralEnabled(uint256 col_idx) {
        require(enabled_collaterals[collateral_addresses[col_idx]], "Collateral disabled");
        _;
    }
 
    /* ========== CONSTRUCTOR ========== */
    
    constructor (
        address _pool_manager_address,
        address _custodian_address,
        address _timelock_address,
        address[] memory _collateral_addresses,
        uint256[] memory _pool_ceilings,
        uint256[] memory _initial_fees,
        address _brax_address,
        address _bxs_address
    ) Owned(_pool_manager_address){
        // Core
        timelock_address = _timelock_address;
        custodian_address = _custodian_address;

        // BRAX and BXS
        BRAX = IBrax(_brax_address);
        BXS = IBxs(_bxs_address);

        // Fill collateral info
        collateral_addresses = _collateral_addresses;
        for (uint256 i = 0; i < _collateral_addresses.length; i++){ 
            // For fast collateral address -> collateral idx lookups later
            collateralAddrToIdx[_collateral_addresses[i]] = i;

            // Set all of the collaterals initially to disabled
            enabled_collaterals[_collateral_addresses[i]] = false;

            // Add in the missing decimals
            missing_decimals.push(uint256(18).sub(ERC20(_collateral_addresses[i]).decimals()));

            // Add in the collateral symbols
            collateral_symbols.push(ERC20(_collateral_addresses[i]).symbol());

            // Initialize unclaimed pool collateral
            unclaimedPoolCollateral.push(0);

            // Initialize paused prices to 1 BTC as a backup
            collateral_prices.push(PRICE_PRECISION);

            // Handle the fees
            minting_fee.push(_initial_fees[0]);
            redemption_fee.push(_initial_fees[1]);
            buyback_fee.push(_initial_fees[2]);
            recollat_fee.push(_initial_fees[3]);

            // Handle the pauses
            mintPaused.push(false);
            redeemPaused.push(false);
            recollateralizePaused.push(false);
            buyBackPaused.push(false);
            borrowingPaused.push(false);
        }

        // Pool ceiling
        pool_ceilings = _pool_ceilings;

        // Set the decimals
        chainlink_brax_btc_decimals = priceFeedBRAXBTC.decimals();
        chainlink_bxs_btc_decimals = priceFeedBXSBTC.decimals();
    }

    /* ========== STRUCTS ========== */
    
    struct CollateralInformation {
        uint256 index;
        string symbol;
        address col_addr;
        bool is_enabled;
        uint256 missing_decs;
        uint256 price;
        uint256 pool_ceiling;
        bool mint_paused;
        bool redeem_paused;
        bool recollat_paused;
        bool buyback_paused;
        bool borrowing_paused;
        uint256 minting_fee;
        uint256 redemption_fee;
        uint256 buyback_fee;
        uint256 recollat_fee;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @dev helper function to help limit volatility in calculations
    function comboCalcBbkRct(uint256 cur, uint256 max, uint256 theo) internal pure returns (uint256) {
        if (cur >= max) {
            // If the hourly limit has already been reached, return 0;
            return 0;
        }
        else {
            // Get the available amount
            uint256 available = max.sub(cur);

            if (theo >= available) {
                // If the the theoretical is more than the available, return the available
                return available;
            }
            else {
                // Otherwise, return the theoretical amount
                return theo;
            }
        } 
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Return the collateral information for a provided address
     * @param collat_address address of a type of collateral, e.g. wBTC or renBTC
     * @return return_data struct containing all data regarding the provided collateral address
     */
    function collateral_information(address collat_address) external view returns (CollateralInformation memory return_data){
        require(enabled_collaterals[collat_address], "Invalid collateral");

        // Get the index
        uint256 idx = collateralAddrToIdx[collat_address];
        
        return_data = CollateralInformation(
            idx, // [0]
            collateral_symbols[idx], // [1]
            collat_address, // [2]
            enabled_collaterals[collat_address], // [3]
            missing_decimals[idx], // [4]
            collateral_prices[idx], // [5]
            pool_ceilings[idx], // [6]
            mintPaused[idx], // [7]
            redeemPaused[idx], // [8]
            recollateralizePaused[idx], // [9]
            buyBackPaused[idx], // [10]
            borrowingPaused[idx], // [11]
            minting_fee[idx], // [12]
            redemption_fee[idx], // [13]
            buyback_fee[idx], // [14]
            recollat_fee[idx] // [15]
        );
    }

    /**
     * @notice Returns a list of all collateral addresses
     * @return addresses list of all collateral addresses
     */
    function allCollaterals() external view returns (address[] memory) {
        return collateral_addresses;
    }

    /**
     * @notice Return current price from chainlink feed for BRAX
     * @return price Current price of BRAX chainlink feed
     */
    function getBRAXPrice() public view returns (uint256) {
        (uint80 roundID, int price, , uint256 updatedAt, uint80 answeredInRound) = priceFeedBRAXBTC.latestRoundData();
        require(price >= 0 && updatedAt!= 0 && answeredInRound >= roundID, "Invalid chainlink price");

        return uint256(price).mul(PRICE_PRECISION).div(10 ** chainlink_brax_btc_decimals);
    }

    /**
     * @notice Return current price from chainlink feed for BXS
     * @return price Current price of BXS chainlink feed
     */
    function getBXSPrice() public view returns (uint256) {
        (uint80 roundID, int price, , uint256 updatedAt, uint80 answeredInRound) = priceFeedBXSBTC.latestRoundData();
        require(price >= 0 && updatedAt!= 0 && answeredInRound >= roundID, "Invalid chainlink price");

        return uint256(price).mul(PRICE_PRECISION).div(10 ** chainlink_bxs_btc_decimals);
    }

    /**
     * @notice Return price of BRAX in the provided collateral token
     * @dev Note: pricing is returned in collateral precision.  For example,
     * @dev getting price for wBTC would be in 8 decimals
     * @param col_idx index of collateral token (e.g. 0 for wBTC, 1 for renBTC)
     * @param brax_amount amount of BRAX to get the equivalent price for
     * @return price price of BRAX in collateral (decimals are equivalent to collateral, not BRAX)
     */
    function getBRAXInCollateral(uint256 col_idx, uint256 brax_amount) public view returns (uint256) {
        return brax_amount.mul(PRICE_PRECISION).div(10 ** missing_decimals[col_idx]).div(collateral_prices[col_idx]);
    }

    /**
     * @notice Return amount of collateral balance not waiting to be redeemed
     * @param col_idx index of collateral token (e.g. 0 for wBTC, 1 for renBTC)
     * @return amount amount of collateral not waiting to be redeemed (E18)
     */
    function freeCollatBalance(uint256 col_idx) public view returns (uint256) {
        return ERC20(collateral_addresses[col_idx]).balanceOf(address(this)).sub(unclaimedPoolCollateral[col_idx]);
    }

    /**
     * @notice Returns BTC value of collateral held in this Brax pool, in E18
     * @return balance_tally total BTC value in pool (E18)
     */
    function collatBtcBalance() external view returns (uint256 balance_tally) {
        balance_tally = 0;

        for (uint256 i = 0; i < collateral_addresses.length; i++){ 
            balance_tally += freeCollatBalance(i).mul(10 ** missing_decimals[i]).mul(collateral_prices[i]).div(PRICE_PRECISION);
        }

    }

    /**
     * @notice Returns the value of excess collateral (E18) held globally, compared to what is needed to maintain the global collateral ratio
     * @dev comboCalcBbkRct() is used to throttle buybacks to avoid dumps during periods of large volatility
     * @return total excess collateral in the system (E18)
     */
    function buybackAvailableCollat() public view returns (uint256) {
        uint256 total_supply = BRAX.totalSupply();
        uint256 global_collateral_ratio = BRAX.global_collateral_ratio();
        uint256 global_collat_value = BRAX.globalCollateralValue();

        if (global_collateral_ratio > PRICE_PRECISION) global_collateral_ratio = PRICE_PRECISION; // Handles an overcollateralized contract with CR > 1
        uint256 required_collat_dollar_value_d18 = (total_supply.mul(global_collateral_ratio)).div(PRICE_PRECISION); // Calculates collateral needed to back each 1 BRAX with 1 BTC of collateral at current collat ratio
        
        if (global_collat_value > required_collat_dollar_value_d18) {
            // Get the theoretical buyback amount
            uint256 theoretical_bbk_amt = global_collat_value.sub(required_collat_dollar_value_d18);

            // See how much has collateral has been issued this hour
            uint256 current_hr_bbk = bbkHourlyCum[curEpochHr()];

            // Account for the throttling
            return comboCalcBbkRct(current_hr_bbk, bbkMaxColE18OutPerHour, theoretical_bbk_amt);
        }
        else return 0;
    }

    /**
     * @notice Returns the missing amount of collateral (in E18) needed to maintain the collateral ratio
     * @return balance_tally total BTC value in pool in E18
     */
    function recollatTheoColAvailableE18() public view returns (uint256) {
        uint256 brax_total_supply = BRAX.totalSupply();
        uint256 effective_collateral_ratio = BRAX.globalCollateralValue().mul(PRICE_PRECISION).div(brax_total_supply); // Returns it in 1e8
        
        uint256 desired_collat_e24 = (BRAX.global_collateral_ratio()).mul(brax_total_supply);
        uint256 effective_collat_e24 = effective_collateral_ratio.mul(brax_total_supply);

        // Return 0 if already overcollateralized
        // Otherwise, return the deficiency
        if (effective_collat_e24 >= desired_collat_e24) return 0;
        else {
            return (desired_collat_e24.sub(effective_collat_e24)).div(PRICE_PRECISION);
        }
    }

    /**
     * @notice Returns the value of BXS available to be used for recollats
     * @dev utilizes comboCalcBbkRct to throttle for periods of high volatility
     * @return total value of BXS available for recollateralization
     */
    function recollatAvailableBxs() public view returns (uint256) {
        uint256 bxs_price = getBXSPrice();

        // Get the amount of collateral theoretically available
        uint256 recollat_theo_available_e18 = recollatTheoColAvailableE18();

        // Get the amount of FXS theoretically outputtable
        uint256 bxs_theo_out = recollat_theo_available_e18.mul(PRICE_PRECISION).div(bxs_price);

        // See how much FXS has been issued this hour
        uint256 current_hr_rct = rctHourlyCum[curEpochHr()];

        // Account for the throttling
        return comboCalcBbkRct(current_hr_rct, rctMaxFxsOutPerHour, bxs_theo_out);
    }

    /// @return hour current epoch hour
    function curEpochHr() public view returns (uint256) {
        return (block.timestamp / 3600); // Truncation desired
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @notice Mint BRAX via collateral / BXS combination
     * @param col_idx integer value of the collateral index
     * @param brax_amt Amount of BRAX to mint
     * @param brax_out_min Minimum amount of BRAX to accept
     * @param max_collat_in Maximum amount of collateral to use for minting
     * @param max_bxs_in Maximum amount of BXS to use for minting
     * @param one_to_one_override Boolean flag to indicate using 1:1 BRAX:Collateral for 
     *   minting, ignoring current global collateral ratio of BRAX
     * @return total_brax_mint Amount of BRAX minted
     * @return collat_needed Amount of collateral used
     * @return bxs_needed Amount of BXS used
     */
     function mintBrax(
        uint256 col_idx, 
        uint256 brax_amt,
        uint256 brax_out_min,
        uint256 max_collat_in,
        uint256 max_bxs_in,
        bool one_to_one_override
    ) external collateralEnabled(col_idx) returns (
        uint256 total_brax_mint, 
        uint256 collat_needed, 
        uint256 bxs_needed
    ) {
        require(mintPaused[col_idx] == false, "Minting is paused");

        // Prevent unneccessary mints
        require(getBRAXPrice() >= mint_price_threshold, "Brax price too low");

        uint256 global_collateral_ratio = BRAX.global_collateral_ratio();

        if (one_to_one_override || global_collateral_ratio >= PRICE_PRECISION) { 
            // 1-to-1, overcollateralized, or user selects override
            collat_needed = getBRAXInCollateral(col_idx, brax_amt);
            bxs_needed = 0;
        } else if (global_collateral_ratio == 0) { 
            // Algorithmic
            collat_needed = 0;
            bxs_needed = brax_amt.mul(PRICE_PRECISION).div(getBXSPrice());
        } else { 
            // Fractional
            uint256 brax_for_collat = brax_amt.mul(global_collateral_ratio).div(PRICE_PRECISION);
            uint256 brax_for_bxs = brax_amt.sub(brax_for_collat);
            collat_needed = getBRAXInCollateral(col_idx, brax_for_collat);
            bxs_needed = brax_for_bxs.mul(PRICE_PRECISION).div(getBXSPrice());
        }

        // Subtract the minting fee
        total_brax_mint = (brax_amt.mul(PRICE_PRECISION.sub(minting_fee[col_idx]))).div(PRICE_PRECISION);

        // Check slippages
        require((total_brax_mint >= brax_out_min), "BRAX slippage");
        require((collat_needed <= max_collat_in), "Collat slippage");
        require((bxs_needed <= max_bxs_in), "BXS slippage");

        // Check the pool ceiling
        require(freeCollatBalance(col_idx).add(collat_needed) <= pool_ceilings[col_idx], "Pool ceiling");

        if(bxs_needed > 0) {
            // Take the BXS and collateral first
            BXS.pool_burn_from(msg.sender, bxs_needed);
        }
        TransferHelper.safeTransferFrom(collateral_addresses[col_idx], msg.sender, address(this), collat_needed);

        // Mint the BRAX
        BRAX.pool_mint(msg.sender, total_brax_mint);
    }

    function redeemBrax(
        uint256 col_idx, 
        uint256 brax_amount, 
        uint256 bxs_out_min, 
        uint256 col_out_min
    ) external collateralEnabled(col_idx) returns (
        uint256 collat_out, 
        uint256 bxs_out
    ) {
        require(redeemPaused[col_idx] == false, "Redeeming is paused");

        // Prevent unnecessary redemptions that could adversely affect the FXS price
        require(getBRAXPrice() <= redeem_price_threshold, "Brax price too high");

        uint256 global_collateral_ratio = BRAX.global_collateral_ratio();
        uint256 brax_after_fee = (brax_amount.mul(PRICE_PRECISION.sub(redemption_fee[col_idx]))).div(PRICE_PRECISION);

        // Assumes 1 BTC BRAX in all cases
        if(global_collateral_ratio >= PRICE_PRECISION) { 
            // 1-to-1 or overcollateralized
            collat_out = getBRAXInCollateral(col_idx, brax_after_fee);
            bxs_out = 0;
        } else if (global_collateral_ratio == 0) { 
            // Algorithmic
            bxs_out = brax_after_fee
                            .mul(PRICE_PRECISION)
                            .div(getBXSPrice());
            collat_out = 0;
        } else { 
            // Fractional
            collat_out = getBRAXInCollateral(col_idx, brax_after_fee)
                            .mul(global_collateral_ratio)
                            .div(PRICE_PRECISION);
            bxs_out = brax_after_fee
                            .mul(PRICE_PRECISION.sub(global_collateral_ratio))
                            .div(getBXSPrice()); // PRICE_PRECISIONS CANCEL OUT
        }

        // Checks
        require(collat_out <= (ERC20(collateral_addresses[col_idx])).balanceOf(address(this)).sub(unclaimedPoolCollateral[col_idx]), "Insufficient pool collateral");
        require(collat_out >= col_out_min, "Collateral slippage");
        require(bxs_out >= bxs_out_min, "BXS slippage");

        // Account for the redeem delay
        redeemCollateralBalances[msg.sender][col_idx] = redeemCollateralBalances[msg.sender][col_idx].add(collat_out);
        unclaimedPoolCollateral[col_idx] = unclaimedPoolCollateral[col_idx].add(collat_out);

        redeemBXSBalances[msg.sender] = redeemBXSBalances[msg.sender].add(bxs_out);
        unclaimedPoolBXS = unclaimedPoolBXS.add(bxs_out);

        lastRedeemed[msg.sender] = block.number;
        
        BRAX.pool_burn_from(msg.sender, brax_amount);
        if (bxs_out > 0) {
            BXS.pool_mint(address(this), bxs_out);
        }
    }

    // After a redemption happens, transfer the newly minted BXS and owed collateral from this pool
    // contract to the user. Redemption is split into two functions to prevent flash loans from being able
    // to take out BRAX/collateral from the system, use an AMM to trade the new price, and then mint back into the system.
    function collectRedemption(uint256 col_idx) external returns (uint256 fxs_amount, uint256 collateral_amount) {
        require(redeemPaused[col_idx] == false, "Redeeming is paused");
        require((lastRedeemed[msg.sender].add(redemption_delay)) <= block.number, "Too soon");
        bool sendFXS = false;
        bool sendCollateral = false;

        // Use Checks-Effects-Interactions pattern
        if(redeemBXSBalances[msg.sender] > 0){
            fxs_amount = redeemBXSBalances[msg.sender];
            redeemBXSBalances[msg.sender] = 0;
            unclaimedPoolBXS = unclaimedPoolBXS.sub(fxs_amount);
            sendFXS = true;
        }
        
        if(redeemCollateralBalances[msg.sender][col_idx] > 0){
            collateral_amount = redeemCollateralBalances[msg.sender][col_idx];
            redeemCollateralBalances[msg.sender][col_idx] = 0;
            unclaimedPoolCollateral[col_idx] = unclaimedPoolCollateral[col_idx].sub(collateral_amount);
            sendCollateral = true;
        }

        // Send out the tokens
        if(sendFXS){
            TransferHelper.safeTransfer(address(BXS), msg.sender, fxs_amount);
        }
        if(sendCollateral){
            TransferHelper.safeTransfer(collateral_addresses[col_idx], msg.sender, collateral_amount);
        }
    }

    // Function can be called by an FXS holder to have the protocol buy back FXS with excess collateral value from a desired collateral pool
    // This can also happen if the collateral ratio > 1
    function buyBackFxs(uint256 col_idx, uint256 fxs_amount, uint256 col_out_min) external collateralEnabled(col_idx) returns (uint256 col_out) {
        require(buyBackPaused[col_idx] == false, "Buyback is paused");
        uint256 fxs_price = getBXSPrice();
        uint256 available_excess_collat_dv = buybackAvailableCollat();

        // If the total collateral value is higher than the amount required at the current collateral ratio then buy back up to the possible FXS with the desired collateral
        require(available_excess_collat_dv > 0, "Insuf Collat Avail For BBK");

        // Make sure not to take more than is available
        uint256 fxs_dollar_value_d18 = fxs_amount.mul(fxs_price).div(PRICE_PRECISION);
        require(fxs_dollar_value_d18 <= available_excess_collat_dv, "Insuf Collat Avail For BBK");

        // Get the equivalent amount of collateral based on the market value of FXS provided 
        uint256 collateral_equivalent_d18 = fxs_dollar_value_d18.mul(PRICE_PRECISION).div(collateral_prices[col_idx]);
        col_out = collateral_equivalent_d18.div(10 ** missing_decimals[col_idx]); // In its natural decimals()

        // Subtract the buyback fee
        col_out = (col_out.mul(PRICE_PRECISION.sub(buyback_fee[col_idx]))).div(PRICE_PRECISION);

        // Check for slippage
        require(col_out >= col_out_min, "Collateral slippage");

        // Take in and burn the FXS, then send out the collateral
        BXS.pool_burn_from(msg.sender, fxs_amount);
        TransferHelper.safeTransfer(collateral_addresses[col_idx], msg.sender, col_out);

        // Increment the outbound collateral, in E18, for that hour
        // Used for buyback throttling
        bbkHourlyCum[curEpochHr()] += collateral_equivalent_d18;
    }

    // When the protocol is recollateralizing, we need to give a discount of FXS to hit the new CR target
    // Thus, if the target collateral ratio is higher than the actual value of collateral, minters get FXS for adding collateral
    // This function simply rewards anyone that sends collateral to a pool with the same amount of FXS + the bonus rate
    // Anyone can call this function to recollateralize the protocol and take the extra FXS value from the bonus rate as an arb opportunity
    function recollateralize(uint256 col_idx, uint256 collateral_amount, uint256 bxs_out_min) external collateralEnabled(col_idx) returns (uint256 bxs_out) {
        require(recollateralizePaused[col_idx] == false, "Recollat is paused");
        uint256 collateral_amount_d18 = collateral_amount * (10 ** missing_decimals[col_idx]);
        uint256 bxs_price = getBXSPrice();

        // Get the amount of FXS actually available (accounts for throttling)
        uint256 bxs_actually_available = recollatAvailableBxs();

        // Calculated the attempted amount of FXS
        bxs_out = collateral_amount_d18.mul(PRICE_PRECISION.add(bonus_rate).sub(recollat_fee[col_idx])).div(bxs_price);

        // Make sure there is FXS available
        require(bxs_out <= bxs_actually_available, "Insuf BXS Avail For RCT");

        // Check slippage
        require(bxs_out >= bxs_out_min, "BXS slippage");

        // Don't take in more collateral than the pool ceiling for this token allows
        require(freeCollatBalance(col_idx).add(collateral_amount) <= pool_ceilings[col_idx], "Pool ceiling");

        // Take in the collateral and pay out the BXS
        TransferHelper.safeTransferFrom(collateral_addresses[col_idx], msg.sender, address(this), collateral_amount);
        BXS.pool_mint(msg.sender, bxs_out);

        // Increment the outbound BXS, in E18
        // Used for recollat throttling
        rctHourlyCum[curEpochHr()] += bxs_out;
    }

    /* ========== RESTRICTED FUNCTIONS, MINTER ONLY ========== */

    // Bypasses the gassy mint->redeem cycle for AMOs to borrow collateral
    function amoMinterBorrow(uint256 collateral_amount) external onlyAMOMinters {
        // Checks the col_idx of the minter as an additional safety check
        uint256 minter_col_idx = IBraxAMOMinter(msg.sender).col_idx();

        // Checks to see if borrowing is paused
        require(borrowingPaused[minter_col_idx] == false, "Borrowing is paused");

        // Ensure collateral is enabled
        require(enabled_collaterals[collateral_addresses[minter_col_idx]], "Collateral disabled");

        // Transfer
        TransferHelper.safeTransfer(collateral_addresses[minter_col_idx], msg.sender, collateral_amount);
    }

    /* ========== RESTRICTED FUNCTIONS, CUSTODIAN CAN CALL TOO ========== */

    function toggleMRBR(uint256 col_idx, uint8 tog_idx) external onlyByOwnGovCust {
        if (tog_idx == 0) mintPaused[col_idx] = !mintPaused[col_idx];
        else if (tog_idx == 1) redeemPaused[col_idx] = !redeemPaused[col_idx];
        else if (tog_idx == 2) buyBackPaused[col_idx] = !buyBackPaused[col_idx];
        else if (tog_idx == 3) recollateralizePaused[col_idx] = !recollateralizePaused[col_idx];
        else if (tog_idx == 4) borrowingPaused[col_idx] = !borrowingPaused[col_idx];

        emit MRBRToggled(col_idx, tog_idx);
    }

    /* ========== RESTRICTED FUNCTIONS, GOVERNANCE ONLY ========== */

    /// @notice Add an AMO Minter Address
    /// @param amo_minter_addr Address of the new AMO minter
    function addAMOMinter(address amo_minter_addr) external onlyByOwnGov {
        require(amo_minter_addr != address(0), "Zero address detected");

        // Make sure the AMO Minter has collatBtcBalance()
        uint256 collat_val_e18 = IBraxAMOMinter(amo_minter_addr).collatBtcBalance();
        require(collat_val_e18 >= 0, "Invalid AMO");

        amo_minter_addresses[amo_minter_addr] = true;

        emit AMOMinterAdded(amo_minter_addr);
    }

    /// @notice Remove an AMO Minter Address
    /// @param amo_minter_addr Address of the AMO minter to remove
    function removeAMOMinter(address amo_minter_addr) external onlyByOwnGov {
        amo_minter_addresses[amo_minter_addr] = false;
        
        emit AMOMinterRemoved(amo_minter_addr);
    }

    /** 
     * @notice Set the collateral price for a specific collateral
     * @param col_idx Index of the collateral
     * @param _new_price New price of the collateral
     */
    function setCollateralPrice(uint256 col_idx, uint256 _new_price) external onlyByOwnGov {
        // Only to be used for collateral without chainlink price feed
        // Immediate priorty to get a price feed in place
        collateral_prices[col_idx] = _new_price;

        emit CollateralPriceSet(col_idx, _new_price);
    }

    /**
     * @notice Toggles collateral for use in the pool
     * @param col_idx Index of the collateral to be enabled
     */
    function toggleCollateral(uint256 col_idx) external onlyByOwnGov {
        address col_address = collateral_addresses[col_idx];
        enabled_collaterals[col_address] = !enabled_collaterals[col_address];

        emit CollateralToggled(col_idx, enabled_collaterals[col_address]);
    }

    /**
     * @notice Set the ceiling of collateral allowed for minting
     * @param col_idx Index of the collateral to be modified
     * @param new_ceiling New ceiling amount of collateral
     */
    function setPoolCeiling(uint256 col_idx, uint256 new_ceiling) external onlyByOwnGov {
        pool_ceilings[col_idx] = new_ceiling;

        emit PoolCeilingSet(col_idx, new_ceiling);
    }

    /**
     * @notice Set the fees of collateral allowed for minting
     * @param col_idx Index of the collateral to be modified
     * @param new_mint_fee New mint fee for collateral
     * @param new_redeem_fee New redemption fee for collateral
     * @param new_buyback_fee New buyback fee for collateral
     * @param new_recollat_fee New recollateralization fee for collateral
     */
    function setFees(uint256 col_idx, uint256 new_mint_fee, uint256 new_redeem_fee, uint256 new_buyback_fee, uint256 new_recollat_fee) external onlyByOwnGov {
        minting_fee[col_idx] = new_mint_fee;
        redemption_fee[col_idx] = new_redeem_fee;
        buyback_fee[col_idx] = new_buyback_fee;
        recollat_fee[col_idx] = new_recollat_fee;

        emit FeesSet(col_idx, new_mint_fee, new_redeem_fee, new_buyback_fee, new_recollat_fee);
    }

    function setPoolParameters(uint256 new_bonus_rate, uint256 new_redemption_delay) external onlyByOwnGov {
        bonus_rate = new_bonus_rate;
        redemption_delay = new_redemption_delay;
        emit PoolParametersSet(new_bonus_rate, new_redemption_delay);
    }

    function setPriceThresholds(uint256 new_mint_price_threshold, uint256 new_redeem_price_threshold) external onlyByOwnGov {
        mint_price_threshold = new_mint_price_threshold;
        redeem_price_threshold = new_redeem_price_threshold;
        emit PriceThresholdsSet(new_mint_price_threshold, new_redeem_price_threshold);
    }

    function setBbkRctPerHour(uint256 _bbkMaxColE18OutPerHour, uint256 _rctMaxFxsOutPerHour) external onlyByOwnGov {
        bbkMaxColE18OutPerHour = _bbkMaxColE18OutPerHour;
        rctMaxFxsOutPerHour = _rctMaxFxsOutPerHour;
        emit BbkRctPerHourSet(_bbkMaxColE18OutPerHour, _rctMaxFxsOutPerHour);
    }

    // Set the Chainlink oracles
    function setOracles(address _brax_btc_chainlink_addr, address _bxs_btc_chainlink_addr) external onlyByOwnGov {
        // Set the instances
        priceFeedBRAXBTC = AggregatorV3Interface(_brax_btc_chainlink_addr);
        priceFeedBXSBTC = AggregatorV3Interface(_bxs_btc_chainlink_addr);

        // Set the decimals
        chainlink_brax_btc_decimals = priceFeedBRAXBTC.decimals();
        chainlink_bxs_btc_decimals = priceFeedBXSBTC.decimals();
        
        emit OraclesSet(_brax_btc_chainlink_addr, _bxs_btc_chainlink_addr);
    }

    function setCustodian(address new_custodian) external onlyByOwnGov {
        custodian_address = new_custodian;

        emit CustodianSet(new_custodian);
    }

    function setTimelock(address new_timelock) external onlyByOwnGov {
        timelock_address = new_timelock;

        emit TimelockSet(new_timelock);
    }

    /* ========== EVENTS ========== */
    event CollateralToggled(uint256 col_idx, bool new_state);
    event PoolCeilingSet(uint256 col_idx, uint256 new_ceiling);
    event FeesSet(uint256 col_idx, uint256 new_mint_fee, uint256 new_redeem_fee, uint256 new_buyback_fee, uint256 new_recollat_fee);
    event PoolParametersSet(uint256 new_bonus_rate, uint256 new_redemption_delay);
    event PriceThresholdsSet(uint256 new_bonus_rate, uint256 new_redemption_delay);
    event BbkRctPerHourSet(uint256 bbkMaxColE18OutPerHour, uint256 rctMaxFxsOutPerHour);
    event AMOMinterAdded(address amo_minter_addr);
    event AMOMinterRemoved(address amo_minter_addr);
    event OraclesSet(address brax_usd_chainlink_addr, address bxs_usd_chainlink_addr);
    event CustodianSet(address new_custodian);
    event TimelockSet(address new_timelock);
    event MRBRToggled(uint256 col_idx, uint8 tog_idx);
    event CollateralPriceSet(uint256 col_idx, uint256 new_price);
}

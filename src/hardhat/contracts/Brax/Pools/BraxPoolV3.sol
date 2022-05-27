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
    address public timelockAddress;
    address public custodianAddress; // Custodian is an EOA (or msig) with pausing privileges only, in case of an emergency

    IBrax private BRAX;
    IBxs private BXS;

    mapping(address => bool) public amoMinterAddresses; // minter address -> is it enabled
    // TODO: Get aggregator
    // IMPORTANT - set to random chainlink contract for testing
    AggregatorV3Interface public priceFeedBRAXBTC = AggregatorV3Interface(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    // TODO: Get aggregator
    // IMPORTANT - set to random chainlink contract for testing
    AggregatorV3Interface public priceFeedBXSBTC = AggregatorV3Interface(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    uint256 private chainlinkBraxBtcDecimals;
    uint256 private chainlinkBxsBtcDecimals;

    // Collateral
    address[] public collateralAddresses;
    string[] public collateralSymbols;
    uint256[] public missingDecimals; // Number of decimals needed to get to E18. collateral index -> missingDecimals
    uint256[] public poolCeilings; // Total across all collaterals. Accounts for missingDecimals
    uint256[] public collateralPrices; // Stores price of the collateral, if price is paused.  Currently hardcoded at 1:1 BTC. CONSIDER ORACLES EVENTUALLY!!!
    mapping(address => uint256) public collateralAddrToIdx; // collateral addr -> collateral index
    mapping(address => bool) public enabledCollaterals; // collateral address -> is it enabled
    
    // Redeem related
    mapping (address => uint256) public redeemBXSBalances;
    mapping (address => mapping(uint256 => uint256)) public redeemCollateralBalances; // Address -> collateral index -> balance
    uint256[] public unclaimedPoolCollateral; // collateral index -> balance
    uint256 public unclaimedPoolBXS;
    mapping (address => uint256) public lastRedeemed; // Collateral independent
    uint256 public redemptionDelay = 2; // Number of blocks to wait before being able to collectRedemption()
    uint256 public redeemPriceThreshold = 99000000; // 0.99 BTC
    uint256 public mintPriceThreshold = 101000000; // 1.01 BTC
    
    // Buyback related
    mapping(uint256 => uint256) public bbkHourlyCum; // Epoch hour ->  Collat out in that hour (E18)
    uint256 public bbkMaxColE18OutPerHour = 1e18;

    // Recollat related
    mapping(uint256 => uint256) public rctHourlyCum; // Epoch hour ->  BXS out in that hour
    uint256 public rctMaxBxsOutPerHour = 1000e18;

    // Fees and rates
    // getters are in collateralInformation()
    uint256[] private mintingFee;
    uint256[] private redemptionFee;
    uint256[] private buybackFee;
    uint256[] private recollatFee;
    uint256 public bonusRate; // Bonus rate on BXS minted during recollateralize(); 6 decimals of precision, set to 0.75% on genesis
    
    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e8;

    // Pause variables
    // getters are in collateralInformation()
    bool[] private mintPaused; // Collateral-specific
    bool[] private redeemPaused; // Collateral-specific
    bool[] private recollateralizePaused; // Collateral-specific
    bool[] private buyBackPaused; // Collateral-specific
    bool[] private borrowingPaused; // Collateral-specific

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require(msg.sender == timelockAddress || msg.sender == owner, "Not owner or timelock");
        _;
    }

    modifier onlyByOwnGovCust() {
        require(msg.sender == timelockAddress || msg.sender == owner || msg.sender == custodianAddress, "Not owner, tlck, or custd");
        _;
    }

    modifier onlyAMOMinters() {
        require(amoMinterAddresses[msg.sender], "Not an AMO Minter");
        _;
    }

    modifier collateralEnabled(uint256 colIdx) {
        require(enabledCollaterals[collateralAddresses[colIdx]], "Collateral disabled");
        _;
    }
 
    /* ========== CONSTRUCTOR ========== */
    
    constructor (
        address _poolManagerAddress,
        address _custodianAddress,
        address _timelockAddress,
        address[] memory _collateralAddresses,
        uint256[] memory _poolCeilings,
        uint256[] memory _initialFees,
        address _braxAddress,
        address _bxsAddress
    ) Owned(_poolManagerAddress){
        // Core
        timelockAddress = _timelockAddress;
        custodianAddress = _custodianAddress;

        // BRAX and BXS
        BRAX = IBrax(_braxAddress);
        BXS = IBxs(_bxsAddress);

        // Fill collateral info
        collateralAddresses = _collateralAddresses;
        for (uint256 i = 0; i < _collateralAddresses.length; i++){ 
            // For fast collateral address -> collateral idx lookups later
            collateralAddrToIdx[_collateralAddresses[i]] = i;

            // Set all of the collaterals initially to disabled
            enabledCollaterals[_collateralAddresses[i]] = false;

            // Add in the missing decimals
            missingDecimals.push(uint256(18).sub(ERC20(_collateralAddresses[i]).decimals()));

            // Add in the collateral symbols
            collateralSymbols.push(ERC20(_collateralAddresses[i]).symbol());

            // Initialize unclaimed pool collateral
            unclaimedPoolCollateral.push(0);

            // Initialize paused prices to 1 BTC as a backup
            collateralPrices.push(PRICE_PRECISION);

            // Handle the fees
            mintingFee.push(_initialFees[0]);
            redemptionFee.push(_initialFees[1]);
            buybackFee.push(_initialFees[2]);
            recollatFee.push(_initialFees[3]);

            // Handle the pauses
            mintPaused.push(false);
            redeemPaused.push(false);
            recollateralizePaused.push(false);
            buyBackPaused.push(false);
            borrowingPaused.push(false);
        }

        // Pool ceiling
        poolCeilings = _poolCeilings;

        // Set the decimals
        chainlinkBraxBtcDecimals = priceFeedBRAXBTC.decimals();
        chainlinkBxsBtcDecimals = priceFeedBXSBTC.decimals();
    }

    /* ========== STRUCTS ========== */
    
    struct CollateralInformation {
        uint256 index;
        string symbol;
        address colAddr;
        bool isEnabled;
        uint256 missingDecs;
        uint256 price;
        uint256 poolCeiling;
        bool mintPaused;
        bool redeemPaused;
        bool recollatPaused;
        bool buybackPaused;
        bool borrowingPaused;
        uint256 mintingFee;
        uint256 redemptionFee;
        uint256 buybackFee;
        uint256 recollatFee;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Compute the threshold for buyback and recollateralization to throttle
     * @notice both in times of high volatility
     * @param cur Current amount already consumed in the current hour
     * @param max Maximum allowable in the current hour
     * @param theo Amount to theoretically distribute, used to check against available amounts
     * @return amount Amount allowable to distribute
     */
    /// @dev helper function to help limit volatility in calculations
    function comboCalcBbkRct(uint256 cur, uint256 max, uint256 theo) internal pure returns (uint256 amount) {
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
     * @param collatAddress address of a type of collateral, e.g. wBTC or renBTC
     * @return returnData struct containing all data regarding the provided collateral address
     */
    function collateralInformation(address collatAddress) external view returns (CollateralInformation memory returnData){
        require(enabledCollaterals[collatAddress], "Invalid collateral");

        // Get the index
        uint256 idx = collateralAddrToIdx[collatAddress];
        
        returnData = CollateralInformation(
            idx, // [0]
            collateralSymbols[idx], // [1]
            collatAddress, // [2]
            enabledCollaterals[collatAddress], // [3]
            missingDecimals[idx], // [4]
            collateralPrices[idx], // [5]
            poolCeilings[idx], // [6]
            mintPaused[idx], // [7]
            redeemPaused[idx], // [8]
            recollateralizePaused[idx], // [9]
            buyBackPaused[idx], // [10]
            borrowingPaused[idx], // [11]
            mintingFee[idx], // [12]
            redemptionFee[idx], // [13]
            buybackFee[idx], // [14]
            recollatFee[idx] // [15]
        );
    }

    /**
     * @notice Returns a list of all collateral addresses
     * @return addresses list of all collateral addresses
     */
    function allCollaterals() external view returns (address[] memory addresses) {
        return collateralAddresses;
    }

    /**
     * @notice Return current price from chainlink feed for BRAX
     * @return braxPrice Current price of BRAX chainlink feed
     */
    function getBRAXPrice() public view returns (uint256 braxPrice) {
        (uint80 roundID, int price, , uint256 updatedAt, uint80 answeredInRound) = priceFeedBRAXBTC.latestRoundData();
        require(price >= 0 && updatedAt!= 0 && answeredInRound >= roundID, "Invalid chainlink price");

        return uint256(price).mul(PRICE_PRECISION).div(10 ** chainlinkBraxBtcDecimals);
    }

    /**
     * @notice Return current price from chainlink feed for BXS
     * @return bxsPrice Current price of BXS chainlink feed
     */
    function getBXSPrice() public view returns (uint256 bxsPrice) {
        (uint80 roundID, int price, , uint256 updatedAt, uint80 answeredInRound) = priceFeedBXSBTC.latestRoundData();
        require(price >= 0 && updatedAt!= 0 && answeredInRound >= roundID, "Invalid chainlink price");

        return uint256(price).mul(PRICE_PRECISION).div(10 ** chainlinkBxsBtcDecimals);
    }

    /**
     * @notice Return price of BRAX in the provided collateral token
     * @dev Note: pricing is returned in collateral precision.  For example,
     * @dev getting price for wBTC would be in 8 decimals
     * @param colIdx index of collateral token (e.g. 0 for wBTC, 1 for renBTC)
     * @param braxAmount amount of BRAX to get the equivalent price for
     * @return braxPrice price of BRAX in collateral (decimals are equivalent to collateral, not BRAX)
     */
    function getBRAXInCollateral(uint256 colIdx, uint256 braxAmount) public view returns (uint256 braxPrice) {
        return braxAmount.mul(PRICE_PRECISION).div(10 ** missingDecimals[colIdx]).div(collateralPrices[colIdx]);
    }

    /**
     * @notice Return amount of collateral balance not waiting to be redeemed
     * @param colIdx index of collateral token (e.g. 0 for wBTC, 1 for renBTC)
     * @return collatAmount amount of collateral not waiting to be redeemed (E18)
     */
    function freeCollatBalance(uint256 colIdx) public view returns (uint256 collatAmount) {
        return ERC20(collateralAddresses[colIdx]).balanceOf(address(this)).sub(unclaimedPoolCollateral[colIdx]);
    }

    /**
     * @notice Returns BTC value of collateral held in this Brax pool, in E18
     * @return balanceTally total BTC value in pool (E18)
     */
    function collatBtcBalance() external view returns (uint256 balanceTally) {
        balanceTally = 0;

        for (uint256 i = 0; i < collateralAddresses.length; i++){ 
            balanceTally += freeCollatBalance(i).mul(10 ** missingDecimals[i]).mul(collateralPrices[i]).div(PRICE_PRECISION);
        }

    }

    /**
     * @notice Returns the value of excess collateral (E18) held globally, compared to what is needed to maintain the global collateral ratio
     * @dev comboCalcBbkRct() is used to throttle buybacks to avoid dumps during periods of large volatility
     * @return total excess collateral in the system (E18)
     */
    function buybackAvailableCollat() public view returns (uint256) {
        uint256 totalSupply = BRAX.totalSupply();
        uint256 globalCollateralRatio = BRAX.globalCollateralRatio();
        uint256 globalCollatValue = BRAX.globalCollateralValue();

        if (globalCollateralRatio > PRICE_PRECISION) globalCollateralRatio = PRICE_PRECISION; // Handles an overcollateralized contract with CR > 1
        uint256 requiredCollatDollarValueD18 = (totalSupply.mul(globalCollateralRatio)).div(PRICE_PRECISION); // Calculates collateral needed to back each 1 BRAX with 1 BTC of collateral at current collat ratio
        
        if (globalCollatValue > requiredCollatDollarValueD18) {
            // Get the theoretical buyback amount
            uint256 theoreticalBbkAmt = globalCollatValue.sub(requiredCollatDollarValueD18);

            // See how much has collateral has been issued this hour
            uint256 currentHrBbk = bbkHourlyCum[curEpochHr()];

            // Account for the throttling
            return comboCalcBbkRct(currentHrBbk, bbkMaxColE18OutPerHour, theoreticalBbkAmt);
        }
        else return 0;
    }

    /**
     * @notice Returns the missing amount of collateral (in E18) needed to maintain the collateral ratio
     * @return balanceTally total BTC value in pool in E18
     */
    function recollatTheoColAvailableE18() public view returns (uint256 balanceTally) {
        uint256 braxTotalSupply = BRAX.totalSupply();
        uint256 effectiveCollateralRatio = BRAX.globalCollateralValue().mul(PRICE_PRECISION).div(braxTotalSupply); // Returns it in 1e8
        
        uint256 desiredCollatE24 = (BRAX.globalCollateralRatio()).mul(braxTotalSupply);
        uint256 effectiveCollatE24 = effectiveCollateralRatio.mul(braxTotalSupply);

        // Return 0 if already overcollateralized
        // Otherwise, return the deficiency
        if (effectiveCollatE24 >= desiredCollatE24) return 0;
        else {
            return (desiredCollatE24.sub(effectiveCollatE24)).div(PRICE_PRECISION);
        }
    }

    /**
     * @notice Returns the value of BXS available to be used for recollats
     * @dev utilizes comboCalcBbkRct to throttle for periods of high volatility
     * @return total value of BXS available for recollateralization
     */
    function recollatAvailableBxs() public view returns (uint256) {
        uint256 bxsPrice = getBXSPrice();

        // Get the amount of collateral theoretically available
        uint256 recollatTheoAvailableE18 = recollatTheoColAvailableE18();

        // Get the amount of FXS theoretically outputtable
        uint256 bxsTheoOut = recollatTheoAvailableE18.mul(PRICE_PRECISION).div(bxsPrice);

        // See how much FXS has been issued this hour
        uint256 currentHrRct = rctHourlyCum[curEpochHr()];

        // Account for the throttling
        return comboCalcBbkRct(currentHrRct, rctMaxBxsOutPerHour, bxsTheoOut);
    }

    /// @return hour current epoch hour
    function curEpochHr() public view returns (uint256) {
        return (block.timestamp / 3600); // Truncation desired
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @notice Mint BRAX via collateral / BXS combination
     * @param colIdx integer value of the collateral index
     * @param braxAmt Amount of BRAX to mint
     * @param braxOutMin Minimum amount of BRAX to accept
     * @param maxCollatIn Maximum amount of collateral to use for minting
     * @param maxBxsIn Maximum amount of BXS to use for minting
     * @param oneToOneOverride Boolean flag to indicate using 1:1 BRAX:Collateral for 
     *   minting, ignoring current global collateral ratio of BRAX
     * @return totalBraxMint Amount of BRAX minted
     * @return collatNeeded Amount of collateral used
     * @return bxsNeeded Amount of BXS used
     */
     function mintBrax(
        uint256 colIdx, 
        uint256 braxAmt,
        uint256 braxOutMin,
        uint256 maxCollatIn,
        uint256 maxBxsIn,
        bool oneToOneOverride
    ) external collateralEnabled(colIdx) returns (
        uint256 totalBraxMint, 
        uint256 collatNeeded, 
        uint256 bxsNeeded
    ) {
        require(mintPaused[colIdx] == false, "Minting is paused");

        // Prevent unneccessary mints
        require(getBRAXPrice() >= mintPriceThreshold, "Brax price too low");

        uint256 globalCollateralRatio = BRAX.globalCollateralRatio();

        if (oneToOneOverride || globalCollateralRatio >= PRICE_PRECISION) { 
            // 1-to-1, overcollateralized, or user selects override
            collatNeeded = getBRAXInCollateral(colIdx, braxAmt);
            bxsNeeded = 0;
        } else if (globalCollateralRatio == 0) { 
            // Algorithmic
            collatNeeded = 0;
            bxsNeeded = braxAmt.mul(PRICE_PRECISION).div(getBXSPrice());
        } else { 
            // Fractional
            uint256 braxForCollat = braxAmt.mul(globalCollateralRatio).div(PRICE_PRECISION);
            uint256 braxForBxs = braxAmt.sub(braxForCollat);
            collatNeeded = getBRAXInCollateral(colIdx, braxForCollat);
            bxsNeeded = braxForBxs.mul(PRICE_PRECISION).div(getBXSPrice());
        }

        // Subtract the minting fee
        totalBraxMint = (braxAmt.mul(PRICE_PRECISION.sub(mintingFee[colIdx]))).div(PRICE_PRECISION);

        // Check slippages
        require((totalBraxMint >= braxOutMin), "BRAX slippage");
        require((collatNeeded <= maxCollatIn), "Collat slippage");
        require((bxsNeeded <= maxBxsIn), "BXS slippage");

        // Check the pool ceiling
        require(freeCollatBalance(colIdx).add(collatNeeded) <= poolCeilings[colIdx], "Pool ceiling");

        if(bxsNeeded > 0) {
            // Take the BXS and collateral first
            BXS.poolBurnFrom(msg.sender, bxsNeeded);
        }
        TransferHelper.safeTransferFrom(collateralAddresses[colIdx], msg.sender, address(this), collatNeeded);

        // Mint the BRAX
        BRAX.poolMint(msg.sender, totalBraxMint);
    }

    /**
     * @notice Redeem BRAX for BXS / Collateral combination
     * @param colIdx integer value of the collateral index
     * @param braxAmount Amount of BRAX to redeem
     * @param bxsOutMin Minimum amount of BXS to redeem for
     * @param colOutMin Minimum amount of collateral to redeem for
     * @return collatOut Amount of collateral redeemed
     * @return bxsOut Amount of BXS redeemed
     */
    function redeemBrax(
        uint256 colIdx, 
        uint256 braxAmount, 
        uint256 bxsOutMin, 
        uint256 colOutMin
    ) external collateralEnabled(colIdx) returns (
        uint256 collatOut, 
        uint256 bxsOut
    ) {
        require(redeemPaused[colIdx] == false, "Redeeming is paused");

        // Prevent unnecessary redemptions that could adversely affect the FXS price
        require(getBRAXPrice() <= redeemPriceThreshold, "Brax price too high");

        uint256 globalCollateralRatio = BRAX.globalCollateralRatio();
        uint256 braxAfterFee = (braxAmount.mul(PRICE_PRECISION.sub(redemptionFee[colIdx]))).div(PRICE_PRECISION);

        // Assumes 1 BTC BRAX in all cases
        if(globalCollateralRatio >= PRICE_PRECISION) { 
            // 1-to-1 or overcollateralized
            collatOut = getBRAXInCollateral(colIdx, braxAfterFee);
            bxsOut = 0;
        } else if (globalCollateralRatio == 0) { 
            // Algorithmic
            bxsOut = braxAfterFee
                            .mul(PRICE_PRECISION)
                            .div(getBXSPrice());
            collatOut = 0;
        } else { 
            // Fractional
            collatOut = getBRAXInCollateral(colIdx, braxAfterFee)
                            .mul(globalCollateralRatio)
                            .div(PRICE_PRECISION);
            bxsOut = braxAfterFee
                            .mul(PRICE_PRECISION.sub(globalCollateralRatio))
                            .div(getBXSPrice()); // PRICE_PRECISIONS CANCEL OUT
        }

        // Checks
        require(collatOut <= (ERC20(collateralAddresses[colIdx])).balanceOf(address(this)).sub(unclaimedPoolCollateral[colIdx]), "Insufficient pool collateral");
        require(collatOut >= colOutMin, "Collateral slippage");
        require(bxsOut >= bxsOutMin, "BXS slippage");

        // Account for the redeem delay
        redeemCollateralBalances[msg.sender][colIdx] = redeemCollateralBalances[msg.sender][colIdx].add(collatOut);
        unclaimedPoolCollateral[colIdx] = unclaimedPoolCollateral[colIdx].add(collatOut);

        redeemBXSBalances[msg.sender] = redeemBXSBalances[msg.sender].add(bxsOut);
        unclaimedPoolBXS = unclaimedPoolBXS.add(bxsOut);

        lastRedeemed[msg.sender] = block.number;
        
        BRAX.poolBurnFrom(msg.sender, braxAmount);
        if (bxsOut > 0) {
            BXS.poolMint(address(this), bxsOut);
        }
    }


    /**
     * @notice Collect collateral and BXS from redemption pool
     * @dev Redemption is split into two functions to prevent flash loans removing 
     * @dev BXS/collateral from the system, use an AMM to trade new price and then mint back
     * @param colIdx integer value of the collateral index
     * @return bxsAmount Amount of BXS redeemed
     * @return collateralAmount Amount of collateral redeemed
     */ 
    function collectRedemption(uint256 colIdx) external returns (uint256 bxsAmount, uint256 collateralAmount) {
        require(redeemPaused[colIdx] == false, "Redeeming is paused");
        require((lastRedeemed[msg.sender].add(redemptionDelay)) <= block.number, "Too soon");
        bool sendFXS = false;
        bool sendCollateral = false;

        // Use Checks-Effects-Interactions pattern
        if(redeemBXSBalances[msg.sender] > 0){
            bxsAmount = redeemBXSBalances[msg.sender];
            redeemBXSBalances[msg.sender] = 0;
            unclaimedPoolBXS = unclaimedPoolBXS.sub(bxsAmount);
            sendFXS = true;
        }
        
        if(redeemCollateralBalances[msg.sender][colIdx] > 0){
            collateralAmount = redeemCollateralBalances[msg.sender][colIdx];
            redeemCollateralBalances[msg.sender][colIdx] = 0;
            unclaimedPoolCollateral[colIdx] = unclaimedPoolCollateral[colIdx].sub(collateralAmount);
            sendCollateral = true;
        }

        // Send out the tokens
        if(sendFXS){
            TransferHelper.safeTransfer(address(BXS), msg.sender, bxsAmount);
        }
        if(sendCollateral){
            TransferHelper.safeTransfer(collateralAddresses[colIdx], msg.sender, collateralAmount);
        }
    }

    /**
     * @notice Trigger buy back of BXS with excess collateral from a desired collateral pool
     * @notice when the current collateralization rate > global collateral ratio
     * @param colIdx Index of the collateral to buy back with
     * @param bxsAmount Amount of BXS to buy back
     * @param colOutMin Minimum amount of collateral to use to buyback
     * @return colOut Amount of collateral used to purchase BXS
     */
    function buyBackBxs(uint256 colIdx, uint256 bxsAmount, uint256 colOutMin) external collateralEnabled(colIdx) returns (uint256 colOut) {
        require(buyBackPaused[colIdx] == false, "Buyback is paused");
        uint256 bxsPrice = getBXSPrice();
        uint256 availableExcessCollatDv = buybackAvailableCollat();

        // If the total collateral value is higher than the amount required at the current collateral ratio then buy back up to the possible FXS with the desired collateral
        require(availableExcessCollatDv > 0, "Insuf Collat Avail For BBK");

        // Make sure not to take more than is available
        uint256 bxsDollarValueD18 = bxsAmount.mul(bxsPrice).div(PRICE_PRECISION);
        require(bxsDollarValueD18 <= availableExcessCollatDv, "Insuf Collat Avail For BBK");

        // Get the equivalent amount of collateral based on the market value of FXS provided 
        uint256 collateralEquivalentD18 = bxsDollarValueD18.mul(PRICE_PRECISION).div(collateralPrices[colIdx]);
        colOut = collateralEquivalentD18.div(10 ** missingDecimals[colIdx]); // In its natural decimals()

        // Subtract the buyback fee
        colOut = (colOut.mul(PRICE_PRECISION.sub(buybackFee[colIdx]))).div(PRICE_PRECISION);

        // Check for slippage
        require(colOut >= colOutMin, "Collateral slippage");

        // Take in and burn the FXS, then send out the collateral
        BXS.poolBurnFrom(msg.sender, bxsAmount);
        TransferHelper.safeTransfer(collateralAddresses[colIdx], msg.sender, colOut);

        // Increment the outbound collateral, in E18, for that hour
        // Used for buyback throttling
        bbkHourlyCum[curEpochHr()] += collateralEquivalentD18;
    }

    /**
     * @notice Reward users who send collateral to a pool with the same amount of BXS + set bonus rate
     * @notice Anyone can call this function to recollateralize the pool and get extra BXS
     * @param colIdx Index of the collateral to recollateralize
     * @param collateralAmount Amount of collateral being deposited
     * @param bxsOutMin Minimum amount of BXS to accept
     * @return bxsOut Amount of BXS distributed
     */
    function recollateralize(uint256 colIdx, uint256 collateralAmount, uint256 bxsOutMin) external collateralEnabled(colIdx) returns (uint256 bxsOut) {
        require(recollateralizePaused[colIdx] == false, "Recollat is paused");
        uint256 collateralAmountD18 = collateralAmount * (10 ** missingDecimals[colIdx]);
        uint256 bxsPrice = getBXSPrice();

        // Get the amount of FXS actually available (accounts for throttling)
        uint256 bxsActuallyAvailable = recollatAvailableBxs();

        // Calculated the attempted amount of FXS
        bxsOut = collateralAmountD18.mul(PRICE_PRECISION.add(bonusRate).sub(recollatFee[colIdx])).div(bxsPrice);

        // Make sure there is FXS available
        require(bxsOut <= bxsActuallyAvailable, "Insuf BXS Avail For RCT");

        // Check slippage
        require(bxsOut >= bxsOutMin, "BXS slippage");

        // Don't take in more collateral than the pool ceiling for this token allows
        require(freeCollatBalance(colIdx).add(collateralAmount) <= poolCeilings[colIdx], "Pool ceiling");

        // Take in the collateral and pay out the BXS
        TransferHelper.safeTransferFrom(collateralAddresses[colIdx], msg.sender, address(this), collateralAmount);
        BXS.poolMint(msg.sender, bxsOut);

        // Increment the outbound BXS, in E18
        // Used for recollat throttling
        rctHourlyCum[curEpochHr()] += bxsOut;
    }

    /* ========== RESTRICTED FUNCTIONS, MINTER ONLY ========== */

    /**
     * @notice Allow AMO Minters to borrow without gas intensive mint->redeem cycle
     * @param collateralAmount Amount of collateral the AMO minter will borrow
     */
    function amoMinterBorrow(uint256 collateralAmount) external onlyAMOMinters {
        // Checks the colIdx of the minter as an additional safety check
        uint256 minterColIdx = IBraxAMOMinter(msg.sender).colIdx();

        // Checks to see if borrowing is paused
        require(borrowingPaused[minterColIdx] == false, "Borrowing is paused");

        // Ensure collateral is enabled
        require(enabledCollaterals[collateralAddresses[minterColIdx]], "Collateral disabled");

        // Transfer
        TransferHelper.safeTransfer(collateralAddresses[minterColIdx], msg.sender, collateralAmount);
    }

    /* ========== RESTRICTED FUNCTIONS, CUSTODIAN CAN CALL TOO ========== */

    /**
     * @notice Allow AMO Minters to borrow without gas intensive mint->redeem cycle
     * @param colIdx Collateral to toggle data for
     * @param togIdx Specific value to toggle
     * @dev togIdx, 0 = mint, 1 = redeem, 2 = buyback, 3 = recollateralize, 4 = borrowing
     */
    function toggleMRBR(uint256 colIdx, uint8 togIdx) external onlyByOwnGovCust {
        if (togIdx == 0) mintPaused[colIdx] = !mintPaused[colIdx];
        else if (togIdx == 1) redeemPaused[colIdx] = !redeemPaused[colIdx];
        else if (togIdx == 2) buyBackPaused[colIdx] = !buyBackPaused[colIdx];
        else if (togIdx == 3) recollateralizePaused[colIdx] = !recollateralizePaused[colIdx];
        else if (togIdx == 4) borrowingPaused[colIdx] = !borrowingPaused[colIdx];

        emit MRBRToggled(colIdx, togIdx);
    }

    /* ========== RESTRICTED FUNCTIONS, GOVERNANCE ONLY ========== */

    /// @notice Add an AMO Minter Address
    /// @param amoMinterAddr Address of the new AMO minter
    function addAMOMinter(address amoMinterAddr) external onlyByOwnGov {
        require(amoMinterAddr != address(0), "Zero address detected");

        // Make sure the AMO Minter has collatBtcBalance()
        uint256 collatValE18 = IBraxAMOMinter(amoMinterAddr).collatBtcBalance();
        require(collatValE18 >= 0, "Invalid AMO");

        amoMinterAddresses[amoMinterAddr] = true;

        emit AMOMinterAdded(amoMinterAddr);
    }

    /// @notice Remove an AMO Minter Address
    /// @param amoMinterAddr Address of the AMO minter to remove
    function removeAMOMinter(address amoMinterAddr) external onlyByOwnGov {
        amoMinterAddresses[amoMinterAddr] = false;
        
        emit AMOMinterRemoved(amoMinterAddr);
    }

    /** 
     * @notice Set the collateral price for a specific collateral
     * @param colIdx Index of the collateral
     * @param _newPrice New price of the collateral
     */
    function setCollateralPrice(uint256 colIdx, uint256 _newPrice) external onlyByOwnGov {
        // Only to be used for collateral without chainlink price feed
        // Immediate priorty to get a price feed in place
        collateralPrices[colIdx] = _newPrice;

        emit CollateralPriceSet(colIdx, _newPrice);
    }

    /**
     * @notice Toggles collateral for use in the pool
     * @param colIdx Index of the collateral to be enabled
     */
    function toggleCollateral(uint256 colIdx) external onlyByOwnGov {
        address colAddress = collateralAddresses[colIdx];
        enabledCollaterals[colAddress] = !enabledCollaterals[colAddress];

        emit CollateralToggled(colIdx, enabledCollaterals[colAddress]);
    }

    /**
     * @notice Set the ceiling of collateral allowed for minting
     * @param colIdx Index of the collateral to be modified
     * @param newCeiling New ceiling amount of collateral
     */
    function setPoolCeiling(uint256 colIdx, uint256 newCeiling) external onlyByOwnGov {
        poolCeilings[colIdx] = newCeiling;

        emit PoolCeilingSet(colIdx, newCeiling);
    }

    /**
     * @notice Set the fees of collateral allowed for minting
     * @param colIdx Index of the collateral to be modified
     * @param newMintFee New mint fee for collateral
     * @param newRedeemFee New redemption fee for collateral
     * @param newBuybackFee New buyback fee for collateral
     * @param newRecollatFee New recollateralization fee for collateral
     */
    function setFees(uint256 colIdx, uint256 newMintFee, uint256 newRedeemFee, uint256 newBuybackFee, uint256 newRecollatFee) external onlyByOwnGov {
        mintingFee[colIdx] = newMintFee;
        redemptionFee[colIdx] = newRedeemFee;
        buybackFee[colIdx] = newBuybackFee;
        recollatFee[colIdx] = newRecollatFee;

        emit FeesSet(colIdx, newMintFee, newRedeemFee, newBuybackFee, newRecollatFee);
    }

    /**
     * @notice Set the parameters of the pool
     * @param newBonusRate Index of the collateral to be modified
     * @param newRedemptionDelay Number of blocks to wait before being able to collectRedemption()
     */
    function setPoolParameters(uint256 newBonusRate, uint256 newRedemptionDelay) external onlyByOwnGov {
        bonusRate = newBonusRate;
        redemptionDelay = newRedemptionDelay;
        emit PoolParametersSet(newBonusRate, newRedemptionDelay);
    }

    /**
     * @notice Set the price thresholds of the pool, preventing minting or redeeming when trading would be more effective
     * @param newMintPriceThreshold Price at which minting is allowed
     * @param newRedeemPriceThreshold Price at which redemptions are allowed
     */
    function setPriceThresholds(uint256 newMintPriceThreshold, uint256 newRedeemPriceThreshold) external onlyByOwnGov {
        mintPriceThreshold = newMintPriceThreshold;
        redeemPriceThreshold = newRedeemPriceThreshold;
        emit PriceThresholdsSet(newMintPriceThreshold, newRedeemPriceThreshold);
    }

    /**
     * @notice Set the buyback and recollateralization maximum amounts for the pool
     * @param _bbkMaxColE18OutPerHour Maximum amount of collateral per hour to be used for buyback
     * @param _rctMaxBxsOutPerHour Maximum amount of BXS per hour allowed to be given for recollateralization
     */
    function setBbkRctPerHour(uint256 _bbkMaxColE18OutPerHour, uint256 _rctMaxBxsOutPerHour) external onlyByOwnGov {
        bbkMaxColE18OutPerHour = _bbkMaxColE18OutPerHour;
        rctMaxBxsOutPerHour = _rctMaxBxsOutPerHour;
        emit BbkRctPerHourSet(_bbkMaxColE18OutPerHour, _rctMaxBxsOutPerHour);
    }

    /**
     * @notice Set the chainlink oracles for the pool
     * @param _braxBtcChainlinkAddr BRAX / BTC chainlink oracle
     * @param _bxsBtcChainlinkAddr BXS / BTC chainlink oracle
     */
    function setOracles(address _braxBtcChainlinkAddr, address _bxsBtcChainlinkAddr) external onlyByOwnGov {
        // Set the instances
        priceFeedBRAXBTC = AggregatorV3Interface(_braxBtcChainlinkAddr);
        priceFeedBXSBTC = AggregatorV3Interface(_bxsBtcChainlinkAddr);

        // Set the decimals
        chainlinkBraxBtcDecimals = priceFeedBRAXBTC.decimals();
        chainlinkBxsBtcDecimals = priceFeedBXSBTC.decimals();
        
        emit OraclesSet(_braxBtcChainlinkAddr, _bxsBtcChainlinkAddr);
    }

    /**
     * @notice Set the custodian address for the pool
     * @param newCustodian New custodian address
     */
    function setCustodian(address newCustodian) external onlyByOwnGov {
        custodianAddress = newCustodian;

        emit CustodianSet(newCustodian);
    }

    /**
     * @notice Set the timelock address for the pool
     * @param newTimelock New timelock address
     */
    function setTimelock(address newTimelock) external onlyByOwnGov {
        timelockAddress = newTimelock;

        emit TimelockSet(newTimelock);
    }

    /* ========== EVENTS ========== */
    event CollateralToggled(uint256 colIdx, bool newState);
    event PoolCeilingSet(uint256 colIdx, uint256 newCeiling);
    event FeesSet(uint256 colIdx, uint256 newMintFee, uint256 newRedeemFee, uint256 newBuybackFee, uint256 newRecollatFee);
    event PoolParametersSet(uint256 newBonusRate, uint256 newRedemptionDelay);
    event PriceThresholdsSet(uint256 newBonusRate, uint256 newRedemptionDelay);
    event BbkRctPerHourSet(uint256 bbkMaxColE18OutPerHour, uint256 rctMaxBxsOutPerHour);
    event AMOMinterAdded(address amoMinterAddr);
    event AMOMinterRemoved(address amoMinterAddr);
    event OraclesSet(address braxBtcChainlinkAddr, address bxsBtcChainlinkAddr);
    event CustodianSet(address newCustodian);
    event TimelockSet(address newTimelock);
    event MRBRToggled(uint256 colIdx, uint8 togIdx);
    event CollateralPriceSet(uint256 colIdx, uint256 newPrice);
}

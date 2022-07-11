// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

// ======================================================================
// |     ____  ____  ___   _  __    _______                             | 
// |    / __ )/ __ \/   | | |/ /   / ____(____  ____ _____  ________    | 
// |   / __  / /_/ / /| | |   /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / /_/ / _, _/ ___ |/   |   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_____/_/ |_/_/  |_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                    |
// ======================================================================
// ===================== ComboOracle_UniV2_UniV3 ========================
// ======================================================================
// Aggregates prices for SLP, UniV2, and UniV3 style LP tokens

// Brax Finance: https://github.com/BraxFinance

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Jason Huan: https://github.com/jasonhuan
// Sam Kazemian: https://github.com/samkazemian

import "./AggregatorV3Interface.sol";
import "./IPricePerShareOptions.sol";
import "../ERC20/ERC20.sol";
import "../Staking/Owned.sol";
import '../Math/HomoraMath.sol';

// ComboOracle
import "../Oracle/ComboOracle.sol";

// UniV2 / SLP
import "../Uniswap/Interfaces/IUniswapV2Pair.sol";
import "../Uniswap/Interfaces/IUniswapV2Router02.sol";

// UniV3
import "../Uniswap_V3/IUniswapV3Factory.sol";
import "../Uniswap_V3/libraries/TickMath.sol";
import "../Uniswap_V3/libraries/LiquidityAmounts.sol";
import "../Uniswap_V3/periphery/interfaces/INonfungiblePositionManager.sol";
import "../Uniswap_V3/IUniswapV3Pool.sol";
import "../Uniswap_V3/ISwapRouter.sol";

contract ComboOracleUniV2UniV3 is Owned {
    using SafeMath for uint256;
    using HomoraMath for uint256;
    
    /* ========== STATE VARIABLES ========== */
    
    // Core addresses
    address timelockAddress;
    address public braxAddress;
    address public bxsAddress;

    // Oracle info
    ComboOracle public comboOracle;

    // UniV2 / SLP
    IUniswapV2Router02 public router;

    // UniV3
    IUniswapV3Factory public univ3Factory;
    INonfungiblePositionManager public univ3Positions;
    ISwapRouter public univ3Router;

    // Precision
    uint256 public PRECISE_PRICE_PRECISION = 1e18;
    uint256 public PRICE_PRECISION = 1e6;
    uint256 public PRICE_MISSING_MULTIPLIER = 1e12;

    /* ========== STRUCTS ========== */

    // ------------ UniV2 ------------

    struct UniV2LPBasicInfo {
        address lpAddress;
        string tokenName;
        string tokenSymbol;
        address token0;
        address token1;
        uint256 token0Decimals;
        uint256 token1Decimals;
        uint256 token0Reserves;
        uint256 token1Reserves;
        uint256 lpTotalSupply;
    }

    struct UniV2PriceInfo {
        uint256 precisePrice; 
        uint256 shortPrice; 
        string tokenSymbol;
        string tokenName;
        string token0Symbol;
        string token1Symbol;
    }

    // ------------ UniV3 ------------

    struct UniV3NFTBasicInfo {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 token0Decimals; 
        uint256 token1Decimals; 
        uint256 lowestDecimals; 
    }

    struct UniV3NFTValueInfo {
        uint256 token0Value;
        uint256 token1Value;
        uint256 totalValue;
        string token0Symbol;
        string token1Symbol;
        uint256 liquidityPrice;
    }
    
    /* ========== CONSTRUCTOR ========== */

    /***
     * @param _ownerAddress Owner of the contract
     * @param _startingAddresses list of addresses to assign to memory variables
     * 0 = braxAddress
     * 1 = bxsAddress
     * 2 = comboOracle
     * 3 = uniswapV2Router02
     * 4 = univ3Factory
     * 5 = univ3PositionManager
     * 6 = univ3Router
     */
    constructor (
        address _ownerAddress,
        address[] memory _startingAddresses
    ) Owned(_ownerAddress) {

        // Core addresses
        braxAddress = _startingAddresses[0];
        bxsAddress = _startingAddresses[1];

        // Oracle info
        comboOracle = ComboOracle(_startingAddresses[2]);

        // UniV2 / SLP
        router = IUniswapV2Router02(_startingAddresses[3]);

        // UniV3
        univ3Factory = IUniswapV3Factory(_startingAddresses[4]);
        univ3Positions = INonfungiblePositionManager(_startingAddresses[5]);
        univ3Router = ISwapRouter(_startingAddresses[6]);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require(msg.sender == owner || msg.sender == timelockAddress, "You are not an owner or the governance timelock");
        _;
    }

    /* ========== VIEWS ========== */

    /***
     * @notice Returns basic info about the univ2 LP pair
     * @return UniV2LPBasicInfo Struct containing data related to the univ2 pair
     * 0 = pair address
     * 1 = pair name
     * 2 = pary symbol
     * 3 = token0 address
     * 4 = token1 address
     * 5 = token0 decimals
     * 6 = token1 decimals
     * 7 = token0 reserves
     * 8 = token1 reserves
     * 9 = univ2 pair total supply
     */
    function uniV2LPBasicInfo(address pairAddress) public view returns (UniV2LPBasicInfo memory) {
        // Instantiate the pair
        IUniswapV2Pair thePair = IUniswapV2Pair(pairAddress);

        // Get the reserves
        (uint256 reserve0, uint256 reserve1, ) = (thePair.getReserves());

        // Get the token1 address
        address token0 = thePair.token0();
        address token1 = thePair.token1();

        // Return
        return UniV2LPBasicInfo(
            pairAddress, // [0]
            thePair.name(), // [1]
            thePair.symbol(), // [2]
            token0, // [3]
            token1, // [4]
            ERC20(token0).decimals(), // [5]
            ERC20(token1).decimals(), // [6]
            reserve0, // [7]
            reserve1, // [8]
            thePair.totalSupply() // [9]
        );
    }

    /***
     * @notice Return the fair price of the univ2 pair
     * @dev Uses the Alpha Homora Fair LP Pricing Method (flash loan resistant)
     * @dev https://cmichel.io/pricing-lp-tokens/
     * @dev https://blog.alphafinance.io/fair-lp-token-pricing/
     * @dev https://github.com/AlphaFinanceLab/alpha-homora-v2-contract/blob/master/contracts/oracle/UniswapV2Oracle.sol
     * @param lpTokenAddress Address of the token to get a price for
     * @return UniV2PriceInfo Struct containing pricing data
     * 0 = Precise Price
     * 1 = Price normalized to decimals of the token
     * 2 = Token Symbol
     * 3 = Token Name
     * 4 = Token0 symbol
     * 5 = Token1 symbol
     */
    function uniV2LPPriceInfo(address lpTokenAddress) public view returns (UniV2PriceInfo memory) {
        // Get info about the LP token
        UniV2LPBasicInfo memory lpBasicInfo = uniV2LPBasicInfo(lpTokenAddress);

        // Get the price of ETH in USD
        // TODO: Update to use BTC price
        uint256 ethPrice = comboOracle.getETHPricePrecise();

        // Alpha Homora method
        uint256 precisePrice;
        {
            uint sqrtK = HomoraMath.sqrt(lpBasicInfo.token0Reserves * lpBasicInfo.token1Reserves).fdiv(lpBasicInfo.lpTotalSupply); // in 2**112
            // TODO: Update to use BTC price
            uint px0 = comboOracle.getETHPx112(lpBasicInfo.token0); // in 2**112
            uint px1 = comboOracle.getETHPx112(lpBasicInfo.token1); // in 2**112
            // fair token0 amt: sqrtK * sqrt(px1/px0)
            // fair token1 amt: sqrtK * sqrt(px0/px1)
            // fair lp price = 2 * sqrt(px0 * px1)
            // split into 2 sqrts multiplication to prevent uint overflow (note the 2**112)

            // In ETH per unit of LP, multiplied by 2**112.
            uint256 precisePriceEth112 = (((sqrtK * 2 * HomoraMath.sqrt(px0)) / (2 ** 56)) * HomoraMath.sqrt(px1)) / (2 ** 56);

            // In USD
            // Split into 2 parts to avoid overflows
            uint256 precisePrice56 = precisePriceEth112 / (2 ** 56); 
            precisePrice = (precisePrice56 * ethPrice) / (2 ** 56);
        }

        return UniV2PriceInfo(
            precisePrice, // [0]
            precisePrice / PRICE_MISSING_MULTIPLIER, // [1]
            lpBasicInfo.tokenSymbol, // [2]
            lpBasicInfo.tokenName, // [3]
            ERC20(lpBasicInfo.token0).symbol(), // [4]
            ERC20(lpBasicInfo.token1).symbol() // [5]
        );
    }

    // UniV2 / SLP LP Token Price
    // Reserves method
    /***
     * @notice Returns univ2 token pricing
     * @param lpTokenAddress univ2 LP token address
     * @return UniV2PriceInfo Struct containing 
     */
    function uniV2LPPriceInfoViaReserves(address lpTokenAddress) public view returns (UniV2PriceInfo memory) {
        // Get info about the LP token
        UniV2LPBasicInfo memory lpBasicInfo = uniV2LPBasicInfo(lpTokenAddress);

        // Get the price of one of the tokens. Try token0 first.
        // After that, multiply the price by the reserves, then scale to E18
        // Then multiply by 2 since both sides are equal dollar value
        // Then divide the the total number of LP tokens
        uint256 precisePrice;
        if (comboOracle.has_info(lpBasicInfo.token0)){
            (uint256 tokenPrecisePrice, , ) = comboOracle.getTokenPrice(lpBasicInfo.token0);

            // Multiply by 2 because each token is half of the TVL
            precisePrice = (2 * tokenPrecisePrice * lpBasicInfo.token0Reserves) / lpBasicInfo.lpTotalSupply;

            // Scale to E18
            precisePrice *= (10 ** (uint(18) - lpBasicInfo.token0Decimals));
        }
        else {
            (uint256 tokenPrecisePrice, , ) = comboOracle.getTokenPrice(lpBasicInfo.token1);
            
            // Multiply by 2 because each token is half of the TVL
            precisePrice = (2 * tokenPrecisePrice * lpBasicInfo.token1Reserves) / lpBasicInfo.lpTotalSupply;

            // Scale to E18
            precisePrice *= (10 ** (uint(18) - lpBasicInfo.token1Decimals));
        }

        return UniV2PriceInfo(
            precisePrice, // [0]
            precisePrice / PRICE_MISSING_MULTIPLIER, // [1]
            lpBasicInfo.tokenSymbol, // [2]
            lpBasicInfo.tokenName, // [3]
            ERC20(lpBasicInfo.token0).symbol(), // [4]
            ERC20(lpBasicInfo.token1).symbol() // [5]
        );
    }

    function getUniV3NFTBasicInfo(uint256 tokenId) public view returns (UniV3NFTBasicInfo memory) {
        // Get the position information
        (
            , // [0]
            , // [1]
            address token0, // [2]
            address token1, // [3]
            uint24 fee, // [4]
            int24 tickLower, // [5]
            int24 tickUpper, // [6]
            uint128 liquidity, // [7]
            , // [8]
            , // [9]
            , // [10]
            // [11]
        ) = univ3Positions.positions(tokenId);

        // Get decimals
        uint256 tkn0_dec = ERC20(token0).decimals();
        uint256 tkn1_dec = ERC20(token1).decimals();

        return UniV3NFTBasicInfo(
            token0, // [0]
            token1, // [1]
            fee, // [2]
            tickLower, // [3]
            tickUpper, // [4]
            liquidity, // [5]
            tkn0_dec,  // [6]
            tkn1_dec,  // [7]
            (tkn0_dec < tkn1_dec) ? tkn0_dec : tkn1_dec // [8]
        );
    }

    // Get stats about a particular UniV3 NFT
    function getUniV3NFTValueInfo(uint256 tokenId) public view returns (UniV3NFTValueInfo memory) {
        UniV3NFTBasicInfo memory lpBasicInfo = getUniV3NFTBasicInfo(tokenId);

        // Get pool price info
        uint160 sqrtPriceX96;
        {
            address pool_address = univ3Factory.getPool(lpBasicInfo.token0, lpBasicInfo.token1, lpBasicInfo.fee);
            IUniswapV3Pool the_pool = IUniswapV3Pool(pool_address);
            (sqrtPriceX96, , , , , , ) = the_pool.slot0();
        }

        // Tick math
        uint256 token0_val_usd = 0;
        uint256 token1_val_usd = 0; 
        {
            // Get the amount of each underlying token in each NFT
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lpBasicInfo.tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(lpBasicInfo.tickUpper);

            // Get amount of each token for 0.1% liquidity movement in each direction (1 per mille)
            uint256 liq_pricing_divisor = (10 ** lpBasicInfo.lowestDecimals);
            (uint256 token0_1pm_amt, uint256 token1_1pm_amt) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, uint128(lpBasicInfo.liquidity / liq_pricing_divisor));

            // Get missing decimals
            uint256 token0MissDecMult = 10 ** (uint(18) - lpBasicInfo.token0Decimals);
            uint256 token1MissDecMult = 10 ** (uint(18) - lpBasicInfo.token1Decimals);

            // Get token prices
            // Will revert if ComboOracle doesn't have a price for both token0 and token1
            (uint256 token0PrecisePrice, , ) = comboOracle.getTokenPrice(lpBasicInfo.token0);
            (uint256 token1PrecisePrice, , ) = comboOracle.getTokenPrice(lpBasicInfo.token1);

            // Get the value of each portion
            // Multiply by liq_pricing_divisor as well
            token0_val_usd = (token0_1pm_amt * liq_pricing_divisor * token0PrecisePrice * token0MissDecMult) / PRECISE_PRICE_PRECISION;
            token1_val_usd = (token1_1pm_amt * liq_pricing_divisor * token1PrecisePrice * token1MissDecMult) / PRECISE_PRICE_PRECISION;
        }

        // Return the total value of the UniV3 NFT
        uint256 nft_ttl_val = (token0_val_usd + token1_val_usd);

        // Return
        return UniV3NFTValueInfo(
            token0_val_usd,
            token1_val_usd,
            nft_ttl_val,
            ERC20(lpBasicInfo.token0).symbol(),
            ERC20(lpBasicInfo.token1).symbol(),
            (uint256(lpBasicInfo.liquidity) * PRECISE_PRICE_PRECISION) / nft_ttl_val
        );
    }

    /* ========== RESTRICTED GOVERNANCE FUNCTIONS ========== */

    function setTimelock(address newTimelockAddress) external onlyByOwnGov {
        timelockAddress = newTimelockAddress;
    }

    function setComboOracle(address newComboOracle) external onlyByOwnGov {
        comboOracle = ComboOracle(newComboOracle);
    }

    function setUniV2Addrs(address newRouter) external onlyByOwnGov {
        // UniV2 / SLP
        router = IUniswapV2Router02(newRouter);
    }

    function setUniV3Addrs(address newFactory, address newPositionsNftManager, address newRouter) external onlyByOwnGov {
        // UniV3
        univ3Factory = IUniswapV3Factory(newFactory);
        univ3Positions = INonfungiblePositionManager(newPositionsNftManager);
        univ3Router = ISwapRouter(newRouter);
    }
}
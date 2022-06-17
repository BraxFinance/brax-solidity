// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.11;

// ======================================================================
// |     ____  ____  ___   _  __    _______                             | 
// |    / __ )/ __ \/   | | |/ /   / ____(____  ____ _____  ________    | 
// |   / __  / /_/ / /| | |   /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / /_/ / _, _/ ___ |/   |   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_____/_/ |_/_/  |_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                    |
// ======================================================================
// ====================== ChainlinkOracleWrapper ========================
// ======================================================================
// The Brax.sol contract needs an oracle with a specific ABI, so this is a
// 'middleman' one that lets it read Chainlink data.

// Brax Finance: https://github.com/BraxFinance
// Based off of FRAX: https://github.com/FraxFinance

// FRAX Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna
// Sam Kazemian: https://github.com/samkazemian

// BRAX Modification Author(s)
// mitche50: https://github.com/mitche50

import "../Math/SafeMath.sol";
import "./AggregatorV3Interface.sol";
import "../Staking/Owned.sol";

contract ChainlinkOracleWrapper is Owned {
    using SafeMath for uint256;

    AggregatorV3Interface private priceFeed;

    uint256 public chainlinkDecimals;

    uint256 public PRICE_PRECISION = 1e8;
    uint256 public EXTRA_PRECISION = 1e8;
    address public timelockAddress;
    address public baseToken;

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require(msg.sender == owner || msg.sender == timelockAddress, "Not owner or timelock");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (
        address genCreatorAddress,
        address genTimelockAddress,
        address genOracleAddress,
        address genBaseToken
    ) Owned(genCreatorAddress) {
        timelockAddress = genTimelockAddress;
        baseToken = genBaseToken;

        priceFeed = AggregatorV3Interface(genOracleAddress);
        chainlinkDecimals = priceFeed.decimals();
    }

    /* ========== VIEWS ========== */

    function getPrice() public view returns (uint256 rawPrice, uint256 precisePrice) {
        (uint80 roundID, int price, , uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        require(price >= 0 && updatedAt!= 0 && answeredInRound >= roundID, "Invalid chainlink price");
        
        // E8
        rawPrice = uint256(price).mul(PRICE_PRECISION).div(uint256(10) ** chainlinkDecimals);

        // E16
        precisePrice = uint256(price).mul(PRICE_PRECISION).mul(EXTRA_PRECISION).div(uint256(10) ** chainlinkDecimals);
    }

    // Override the logic of the Uniswap TWAP
    // Expected Parameters: wbtc address, 1e8 precision
    // Returns: Chainlink price (with 1e8 precision)
    function consult(address token, uint amountIn) external view returns (uint amountOut) {
        // safety checks
        require(token == baseToken, "must use base token address");
        require(amountIn == 1e8, "must call with 1e8");

        // needs to return it inverted
        (, uint256 price) = getPrice(); 
        return PRICE_PRECISION.mul(PRICE_PRECISION).mul(EXTRA_PRECISION).div(price);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setChainlinkOracle(address newOracle) external onlyByOwnGov {
        priceFeed = AggregatorV3Interface(newOracle);
        chainlinkDecimals = priceFeed.decimals();
    }

}
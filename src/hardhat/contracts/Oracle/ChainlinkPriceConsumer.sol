// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "./AggregatorV3Interface.sol";

contract ChainlinkPriceConsumer {

    AggregatorV3Interface internal priceFeed;

    constructor (address _priceFeed) public {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /**
     * @return price The latest price
     */
    function getLatestPrice() public view returns (int) {
        (uint80 roundID, int price, , uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        require(price >= 0 && updatedAt!= 0 && answeredInRound >= roundID, "Invalid chainlink price");
        
        return price;
    }

    /**
     * @return decimals Decimals of the price feed  
     */
    function getDecimals() public view returns (uint8) {
        return priceFeed.decimals();
    }
}
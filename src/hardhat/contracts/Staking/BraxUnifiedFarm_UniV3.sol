// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;
pragma experimental ABIEncoderV2;

// ======================================================================
// |     ____  ____  ___   _  __    _______                             | 
// |    / __ )/ __ \/   | | |/ /   / ____(____  ____ _____  ________    | 
// |   / __  / /_/ / /| | |   /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / /_/ / _, _/ ___ |/   |   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_____/_/ |_/_/  |_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                    |
// ======================================================================
// ======================= BraxUnifiedFarm_UniV3 ======================
// ====================================================================
// For UniV3
// Uses BraxUnifiedFarmTemplate.sol
// Original attributions to https://github.com/FraxFinance/frax-solidity/blob/master/src/hardhat/contracts/Staking/FraxUnifiedFarm_UniV3.sol 

import "./BraxUnifiedFarmTemplate.sol";
import "../Oracle/ComboOracleUniV2UniV3.sol";

contract BraxUnifiedFarm_UniV3 is BraxUnifiedFarmTemplate {

    /* ========== STATE VARIABLES ========== */

    // Uniswap V3 related
    INonfungiblePositionManager private stakingTokenNFT = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88); // UniV3 uses an NFT
    int24 public uniTickLower;
    int24 public uniTickUpper;
    uint24 public uniRequiredFee;
    address public uniToken0;
    address public uniToken1;

    // Need to seed a starting token to use both as a basis for braxPerLPToken
    // as well as getting ticks, etc
    uint256 public seedTokenId; 

    // Combo Oracle related
    ComboOracleUniV2UniV3 private comboOracleUniV2UniV3 = ComboOracleUniV2UniV3(address(0));

    // Stake tracking
    mapping(address => LockedNFT[]) public lockedNFTs;


    /* ========== STRUCTS ========== */

    // Struct for the stake
    struct LockedNFT {
        uint256 tokenId; // for Uniswap V3 LPs
        uint256 liquidity;
        uint256 startTimestamp;
        uint256 endingTimestamp;
        uint256 lockMultiplier; // 6 decimals of precision. 1x = 1000000
        int24 tickLower;
        int24 tickUpper;
    }
    
    /* ========== CONSTRUCTOR ========== */

    constructor (
        address genOwner,
        address[] memory genRewardTokens,
        address[] memory genRewardManagers,
        uint256[] memory genRewardRatesManual,
        address[] memory genGaugeControllers,
        address[] memory genRewardDistributors,
        uint256 genSeedTokenId,
        address genVeBXS,
        address genBrax
    ) 
    BraxUnifiedFarmTemplate(genOwner, genRewardTokens, genRewardManagers, genRewardRatesManual, genGaugeControllers, genRewardDistributors, genVeBXS, genBrax)
    {
        // Use the seed token as a template
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            ,
            ,
            ,
            ,

        ) = stakingTokenNFT.positions(genSeedTokenId);

        // Set the UniV3 addresses
        uniToken0 = token0;
        uniToken1 = token1;

        // Check where BRAX is
        if (uniToken0 == braxAddress) braxIsToken0 = true;

        // Fee, Tick, and Liquidity related
        uniRequiredFee = fee;
        uniTickLower = tickLower;
        uniTickUpper = tickUpper;
        
        // Set the seed token id
        seedTokenId = genSeedTokenId;

        // Infinite approve the two tokens to the Positions NFT Manager 
        // This saves gas
        ERC20(uniToken0).approve(address(stakingTokenNFT), type(uint256).max);
        ERC20(uniToken1).approve(address(stakingTokenNFT), type(uint256).max);
    }

    /* ============= VIEWS ============= */

    // ------ BRAX RELATED ------

    function braxPerLPToken() public view override returns (uint256) {
        // Used the seeded main NFT token ID as a basis for this
        // Doing this + using braxPerLPStored should save a lot of gas
        ComboOracleUniV2UniV3.UniV3NFTBasicInfo memory NFTBasicInfo = comboOracleUniV2UniV3.getUniV3NFTBasicInfo(seedTokenId);
        ComboOracleUniV2UniV3.UniV3NFTValueInfo memory NFTValueInfo = comboOracleUniV2UniV3.getUniV3NFTValueInfo(seedTokenId);

        if (braxIsToken0) {
            return (NFTValueInfo.token0Value * MULTIPLIER_PRECISION) / NFTBasicInfo.liquidity;
        }
        else {
            return (NFTValueInfo.token1Value * MULTIPLIER_PRECISION) / NFTBasicInfo.liquidity;
        }
    }

    // ------ UNI-V3 RELATED ------

    function checkUniV3NFT(uint256 tokenId, bool failIfFalse) internal view returns (bool isValid, uint256 liquidity, int24 tickLower, int24 tickUpper) {
        (
            ,
            ,
            address _token0,
            address _token1,
            uint24 _fee,
            int24 _tickLower,
            int24 _tickUpper,
            uint256 _liquidity,
            ,
            ,
            ,

        ) = stakingTokenNFT.positions(tokenId);

        // Set initially
        isValid = false;
        liquidity = _liquidity;

        // Do the checks
        if (
            (_token0 == uniToken0) && 
            (_token1 == uniToken1) && 
            (_fee == uniRequiredFee) && 
            (_tickLower == uniTickLower) && 
            (_tickUpper == uniTickUpper)
        ) {
            isValid = true;
        }
        else {
            // More detailed messages removed here to save space
            if (failIfFalse) {
                revert("Wrong token characteristics");
            }
        }
        return (isValid, liquidity, tickLower, tickUpper);
    }

    // ------ ERC721 RELATED ------

    // Needed to indicate that this contract is ERC721 compatible
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ------ LIQUIDITY AND WEIGHTS ------

    // Calculate the combined weight for an account
    function calcCurCombinedWeight(address account) public override view
        returns (
            uint256 oldCombinedWeight,
            uint256 newVebxsMultiplier,
            uint256 newCombinedWeight
        )
    {
        // Get the old combined weight
        oldCombinedWeight = _combinedWeights[account];

        // Get the veBXS multipliers
        // For the calculations, use the midpoint (analogous to midpoint Riemann sum)
        newVebxsMultiplier = veBXSMultiplier(account);

        uint256 midpointVebxsMultiplier;
        if (_lockedLiquidity[account] == 0 && _combinedWeights[account] == 0) {
            // This is only called for the first stake to make sure the veBXS multiplier is not cut in half
            midpointVebxsMultiplier = newVebxsMultiplier;
        }
        else {
            midpointVebxsMultiplier = (newVebxsMultiplier + _vebxsMultiplierStored[account]) / 2;
        }

        // Loop through the locked stakes, first by getting the liquidity * lockMultiplier portion
        newCombinedWeight = 0;
        for (uint256 i = 0; i < lockedNFTs[account].length; i++) {
            LockedNFT memory thisNFT = lockedNFTs[account][i];
            uint256 lockMultiplier = thisNFT.lockMultiplier;

            // If the lock is expired
            if (thisNFT.endingTimestamp <= block.timestamp) {
                // If the lock expired in the time since the last claim, the weight needs to be proportionately averaged this time
                if (lastRewardClaimTime[account] < thisNFT.endingTimestamp){
                    uint256 timeBeforeExpiry = thisNFT.endingTimestamp - lastRewardClaimTime[account];
                    uint256 timeAfterExpiry = block.timestamp - thisNFT.endingTimestamp;

                    // Get the weighted-average lockMultiplier
                    uint256 numerator = (lockMultiplier * timeBeforeExpiry) + (MULTIPLIER_PRECISION * timeAfterExpiry);
                    lockMultiplier = numerator / (timeBeforeExpiry + timeAfterExpiry);
                }
                // Otherwise, it needs to just be 1x
                else {
                    lockMultiplier = MULTIPLIER_PRECISION;
                }
            }

            uint256 liquidity = thisNFT.liquidity;
            uint256 combinedBoostedAmount = (liquidity * (lockMultiplier + midpointVebxsMultiplier)) / MULTIPLIER_PRECISION;
            newCombinedWeight = newCombinedWeight + combinedBoostedAmount;
        }
    }

    // ------ LOCK RELATED ------

    // Return all of the locked NFT positions
    function lockedNFTsOf(address account) external view returns (LockedNFT[] memory) {
        return lockedNFTs[account];
    }

    // Returns the length of the locked NFTs for a given account
    function lockedNFTsOfLength(address account) external view returns (uint256) {
        return lockedNFTs[account].length;
    }

    // // All the locked stakes for a given account [old-school method]
    // function lockedNFTsOfMultiArr(address account) external view returns (
    //     uint256[] memory tokenIds,
    //     uint256[] memory startTimestamps,
    //     uint256[] memory liquidities,
    //     uint256[] memory endingTimestamps,
    //     uint256[] memory lockMultipliers,
    //     int24[] memory tickLowers,
    //     int24[] memory tickUppers
    // ) {
    //     for (uint256 i = 0; i < lockedNFTs[account].length; i++){ 
    //         LockedNFT memory thisNFT = lockedNFTs[account][i];
    //         tokenIds[i] = thisNFT.tokenId;
    //         startTimestamps[i] = thisNFT.startTimestamp;
    //         liquidities[i] = thisNFT.liquidity;
    //         endingTimestamps[i] = thisNFT.endingTimestamp;
    //         lockMultipliers[i] = thisNFT.lockMultiplier;
    //         tickLowers[i] = thisNFT.tickLower;
    //         tickUppers[i] = thisNFT.tickUpper;
    //     }
    // }

    /* =============== MUTATIVE FUNCTIONS =============== */

    // ------ STAKING ------

    function _getStake(address stakerAddress, uint256 tokenId) internal view returns (LockedNFT memory lockedNft, uint256 arrIdx) {
        for (uint256 i = 0; i < lockedNFTs[stakerAddress].length; i++){ 
            if (tokenId == lockedNFTs[stakerAddress][i].tokenId){
                lockedNft = lockedNFTs[stakerAddress][i];
                arrIdx = i;
                break;
            }
        }
        require(lockedNft.tokenId == tokenId, "Stake not found");
        
    }

    // Add additional LPs to an existing locked stake
    // Make sure to do the 2 token approvals to the NFT Position Manager first on the UI
    // NOTE: If useBalofOverride is true, make sure your calling transaction is atomic with the token
    // transfers in to prevent front running!
    function lockAdditional(
        uint256 tokenId, 
        uint256 token0Amt, 
        uint256 token1Amt,
        uint256 token0MinIn, 
        uint256 token1MinIn,
        bool useBalofOverride // Use balanceOf Override
    ) updateRewardAndBalance(msg.sender, true) public {
        // Get the stake and its index
        (LockedNFT memory thisNFT, uint256 theArrayIndex) = _getStake(msg.sender, tokenId);

        // Handle the tokens
        uint256 tk0AmtToUse;
        uint256 tk1AmtToUse;
        if (useBalofOverride){
            // Get the token balances atomically sent to this farming contract
            tk0AmtToUse = ERC20(uniToken0).balanceOf(address(this));
            tk1AmtToUse = ERC20(uniToken1).balanceOf(address(this));
        }
        else {
            // Pull in the two tokens
            tk0AmtToUse = token0Amt;
            tk1AmtToUse = token1Amt;
            TransferHelper.safeTransferFrom(uniToken0, msg.sender, address(this), tk0AmtToUse);
            TransferHelper.safeTransferFrom(uniToken1, msg.sender, address(this), tk1AmtToUse);
        }

        // Calculate the increaseLiquidity parms
        INonfungiblePositionManager.IncreaseLiquidityParams memory incLiqParams = INonfungiblePositionManager.IncreaseLiquidityParams(
            tokenId,
            tk0AmtToUse,
            tk1AmtToUse,
            useBalofOverride ? 0 : token0MinIn, // Ignore slippage if using balanceOf
            useBalofOverride ? 0 : token1MinIn, // Ignore slippage if using balanceOf
            block.timestamp + 604800 // Expiration: 7 days from now
        );

        // Add the liquidity
        ( uint128 addlLiq, ,  ) = stakingTokenNFT.increaseLiquidity(incLiqParams);

        // Checks
        require(addlLiq >= 0, "Must be nonzero");

        // Update the stake
        lockedNFTs[msg.sender][theArrayIndex] = LockedNFT(
            tokenId,
            thisNFT.liquidity + addlLiq,
            thisNFT.startTimestamp,
            thisNFT.endingTimestamp,
            thisNFT.lockMultiplier,
            thisNFT.tickLower,
            thisNFT.tickUpper
        );

        // Update liquidities
        _totalLiquidityLocked += addlLiq;
        _lockedLiquidity[msg.sender] += addlLiq;
        {
            address theProxy = stakerDesignatedProxies[msg.sender];
            if (theProxy != address(0)) proxyLpBalances[theProxy] += addlLiq;
        }

        // Need to call to update the combined weights
        _updateRewardAndBalance(msg.sender, false);
    }

    // Two different stake functions are needed because of delegateCall and msg.sender issues (important for migration)
    function stakeLocked(uint256 tokenId, uint256 secs) nonReentrant external {
        _stakeLocked(msg.sender, msg.sender, tokenId, secs, block.timestamp);
    }

    // If this were not internal, and sourceAddress had an infinite approve, this could be exploitable
    // (pull funds from sourceAddress and stake for an arbitrary stakerAddress)
    function _stakeLocked(
        address stakerAddress,
        address sourceAddress,
        uint256 tokenId,
        uint256 secs,
        uint256 startTimestamp
    ) internal updateRewardAndBalance(stakerAddress, true) {
        require(stakingPaused == false || validMigrators[msg.sender] == true, "Staking paused or in migration");
        require(secs >= lockTimeMin, "Minimum stake time not met");
        require(secs <= lockTimeForMaxMultiplier,"Trying to lock for too long");
        (, uint256 liquidity, int24 tickLower, int24 tickUpper) = checkUniV3NFT(tokenId, true); // Should throw if false

        {
            uint256 lockMultiplier = lockMultiplier(secs);
            lockedNFTs[stakerAddress].push(
                LockedNFT(
                    tokenId,
                    liquidity,
                    startTimestamp,
                    startTimestamp + secs,
                    lockMultiplier,
                    tickLower,
                    tickUpper
                )
            );
        }

        // Pull the tokens from the sourceAddress
        stakingTokenNFT.safeTransferFrom(sourceAddress, address(this), tokenId);

        // Update liquidities
        _totalLiquidityLocked += liquidity;
        _lockedLiquidity[stakerAddress] += liquidity;
        {
            address theProxy = getProxyFor(stakerAddress);
            if (theProxy != address(0)) proxyLpBalances[theProxy] += liquidity;
        }

        // Need to call again to make sure everything is correct
        _updateRewardAndBalance(stakerAddress, false);

        emit LockNFT(stakerAddress, liquidity, tokenId, secs, sourceAddress);
    }

    // ------ WITHDRAWING ------

    // Two different withdrawLocked functions are needed because of delegateCall and msg.sender issues (important for migration)
    function withdrawLocked(uint256 tokenId, address destinationAddress) nonReentrant external {
        require(withdrawalsPaused == false, "Withdrawals paused");
        _withdrawLocked(msg.sender, destinationAddress, tokenId);
    }

    // No withdrawer == msg.sender check needed since this is only internally callable and the checks are done in the wrapper
    // functions like migratorWithdrawLocked() and withdrawLocked()
    function _withdrawLocked(
        address stakerAddress,
        address destinationAddress,
        uint256 tokenId
    ) internal {
        // Collect rewards first and then update the balances
        _getReward(stakerAddress, destinationAddress);

        LockedNFT memory thisNFT;
        thisNFT.liquidity = 0;
        uint256 theArrayIndex;
        for (uint256 i = 0; i < lockedNFTs[stakerAddress].length; i++) {
            if (tokenId == lockedNFTs[stakerAddress][i].tokenId) {
                thisNFT = lockedNFTs[stakerAddress][i];
                theArrayIndex = i;
                break;
            }
        }
        require(thisNFT.tokenId == tokenId, "Token ID not found");
        require(block.timestamp >= thisNFT.endingTimestamp || stakesUnlocked == true || validMigrators[msg.sender] == true, "Stake is still locked!");

        uint256 theLiquidity = thisNFT.liquidity;

        if (theLiquidity > 0) {
            // Update liquidities
            _totalLiquidityLocked -= theLiquidity;
            _lockedLiquidity[stakerAddress] -= theLiquidity;
            {
                address theProxy = getProxyFor(stakerAddress);
                if (theProxy != address(0)) proxyLpBalances[theProxy] -= theLiquidity;
            }

            // Remove the stake from the array
            delete lockedNFTs[stakerAddress][theArrayIndex];

            // Need to call again to make sure everything is correct
            _updateRewardAndBalance(stakerAddress, false);

            // Give the tokens to the destinationAddress
            stakingTokenNFT.safeTransferFrom(address(this), destinationAddress, tokenId);

            emit WithdrawLocked(stakerAddress, theLiquidity, tokenId, destinationAddress);
        }
    }

    function _getRewardExtraLogic(address rewardee, address destinationAddress) internal override {
        // Collect liquidity fees too
        // uint256 accumulatedToken0 = 0;
        // uint256 accumulatedToken1 = 0;
        LockedNFT memory thisNFT;
        for (uint256 i = 0; i < lockedNFTs[rewardee].length; i++) {
            thisNFT = lockedNFTs[rewardee][i];
            
            // Check for null entries
            if (thisNFT.tokenId != 0){
                INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams(
                    thisNFT.tokenId,
                    destinationAddress,
                    type(uint128).max,
                    type(uint128).max
                );
                stakingTokenNFT.collect(collectParams);
                // (uint256 tok0Amt, uint256 tok1Amt) = stakingTokenNFT.collect(collectParams);
                // accumulatedToken0 += tok0Amt;
                // accumulatedToken1 += tok1Amt;
            }
        }
    }

    /* ========== RESTRICTED FUNCTIONS - Curator / migrator callable ========== */

    // [DISABLED FOR SPACE CONCERNS. ALSO, HARD TO GET UNIQUE TOKEN IDS DURING MIGRATIONS?]
    // // Migrator can stake for someone else (they won't be able to withdraw it back though, only stakerAddress can).
    // function migrator_stakeLocked_for(address stakerAddress, uint256 tokenId, uint256 secs, uint256 startTimestamp) external isMigrating {
    //     require(staker_allowed_migrators[stakerAddress][msg.sender] && valid_migrators[msg.sender], "Mig. invalid or unapproved");
    //     _stakeLocked(stakerAddress, msg.sender, tokenId, secs, startTimestamp);
    // }

    // // Used for migrations
    // function migrator_withdraw_locked(address stakerAddress, uint256 tokenId) external isMigrating {
    //     require(staker_allowed_migrators[stakerAddress][msg.sender] && valid_migrators[msg.sender], "Mig. invalid or unapproved");
    //     _withdrawLocked(stakerAddress, msg.sender, tokenId);
    // }
    
    /* ========== RESTRICTED FUNCTIONS - Owner or timelock only ========== */

    // Added to support recovering LP Rewards and other mistaken tokens from other systems to be distributed to holders
    function recoverERC721(address tokenAddress, uint256 tokenId) external onlyByOwnGov {
        // Admin cannot withdraw the staking token from the contract unless currently migrating
        if (!migrationsOn) {
            require(tokenAddress != address(stakingTokenNFT), "Not in migration"); // Only Governance / Timelock can trigger a migration
        }
        
        // Only the owner address can ever receive the recovery withdrawal
        // INonfungiblePositionManager inherits IERC721 so the latter does not need to be imported
        INonfungiblePositionManager(tokenAddress).safeTransferFrom(address(this), owner, tokenId);
    }

    /* ========== EVENTS ========== */

    event LockNFT(address indexed user, uint256 liquidity, uint256 tokenId, uint256 secs, address sourceAddress);
    event WithdrawLocked(address indexed user, uint256 liquidity, uint256 tokenId, address destinationAddress);
}

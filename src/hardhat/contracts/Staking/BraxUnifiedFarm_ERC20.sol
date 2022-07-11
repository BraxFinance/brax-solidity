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
// ======================= BraxUnifiedFarm_ERC20 ======================
// ====================================================================
// For ERC20 Tokens
// Uses BraxUnifiedFarmTemplate.sol
// Original attributions to https://github.com/FraxFinance/frax-solidity/blob/master/src/hardhat/contracts/Staking/FraxUnifiedFarm_ERC20.sol 

import "./BraxUnifiedFarmTemplate.sol";

// -------------------- VARIES --------------------

// G-UNI
// import "../Misc_AMOs/gelato/IGUniPool.sol";

// mStable
// import '../Misc_AMOs/mstable/IFeederPool.sol';

// StakeDAO sdETH-BraxPut
// import '../Misc_AMOs/stakedao/IOpynPerpVault.sol';

// StakeDAO Vault
// import '../Misc_AMOs/stakedao/IStakeDaoVault.sol';

// Uniswap V2
import '../Uniswap/Interfaces/IUniswapV2Pair.sol';

// Vesper
// import '../Misc_AMOs/vesper/IVPool.sol';

// ------------------------------------------------

contract BraxUnifiedFarm_ERC20 is BraxUnifiedFarmTemplate {

    /* ========== STATE VARIABLES ========== */

    // -------------------- VARIES --------------------

    // G-UNI
    // IGUniPool public stakingToken;
    
    // mStable
    // IFeederPool public stakingToken;

    // sdETH-BraxPut Vault
    // IOpynPerpVault public stakingToken;

    // StakeDAO Vault
    // IStakeDaoVault public stakingToken;

    // Uniswap V2
    IUniswapV2Pair public stakingToken;

    // Vesper
    // IVPool public stakingToken;

    // ------------------------------------------------

    // Stake tracking
    mapping(address => LockedStake[]) public lockedStakes;

    /* ========== STRUCTS ========== */

    // Struct for the stake
    struct LockedStake {
        bytes32 kekId;
        uint256 startTimestamp;
        uint256 liquidity;
        uint256 endingTimestamp;
        uint256 lockMultiplier; // 6 decimals of precision. 1x = 1000000
    }
    
    /* ========== CONSTRUCTOR ========== */

    constructor (
        address genOwner,
        address[] memory genRewardTokens,
        address[] memory genRewardManagers,
        uint256[] memory genRewardRatesManual,
        address[] memory genGaugeControllers,
        address[] memory genRewardDistributors,
        address genStakingToken,
        address genVeBXS,
        address genBrax
    )
    BraxUnifiedFarmTemplate(genOwner, genRewardTokens, genRewardManagers, genRewardRatesManual, genGaugeControllers, genRewardDistributors, genVeBXS, genBrax)
    {

        // -------------------- VARIES --------------------
        // G-UNI
        // stakingToken = IGUniPool(genStakingToken);
        // address token0 = address(stakingToken.token0());
        // braxIsToken0 = token0 == braxAddress;

        // mStable
        // stakingToken = IFeederPool(genStakingToken);

        // StakeDAO sdETH-BraxPut Vault
        // stakingToken = IOpynPerpVault(genStakingToken);

        // StakeDAO Vault
        // stakingToken = IStakeDaoVault(genStakingToken);

        // Uniswap V2
        stakingToken = IUniswapV2Pair(genStakingToken);
        address token0 = stakingToken.token0();
        if (token0 == braxAddress) braxIsToken0 = true;
        else braxIsToken0 = false;

        // Vesper
        // stakingToken = IVPool(genStakingToken);
    }

    /* ============= VIEWS ============= */

    // ------ BRAX RELATED ------

    function braxPerLPToken() public view override returns (uint256) {
        // Get the amount of BRAX 'inside' of the lp tokens
        uint256 braxPerLpToken;

        // G-UNI
        // ============================================
        // {
        //     (uint256 reserve0, uint256 reserve1) = stakingToken.getUnderlyingBalances();
        //     uint256 totalBraxReserves = braxIsToken0 ? reserve0 : reserve1;

        //     braxPerLpToken = (totalBraxReserves * 1e18) / stakingToken.totalSupply();
        // }

        // mStable
        // ============================================
        // {
        //     uint256 totalBraxReserves;
        //     (, IFeederPool.BassetData memory vaultData) = (stakingToken.getBasset(braxAddress));
        //     totalBraxReserves = uint256(vaultData.vaultBalance);
        //     braxPerLpToken = (totalBraxReserves * 1e18) / stakingToken.totalSupply();
        // }

        // StakeDAO sdETH-BraxPut Vault
        // ============================================
        // {
        //    uint256 brax3crvHeld = stakingToken.totalUnderlyingControlled();
        
        //    // Optimistically assume 50/50 BRAX/3CRV ratio in the metapool to save gas
        //    braxPerLpToken = ((brax3crvHeld * 1e18) / stakingToken.totalSupply()) / 2;
        // }

        // StakeDAO Vault
        // ============================================
        // {
        //    uint256 brax3crvHeld = stakingToken.balance();
        
        //    // Optimistically assume 50/50 BRAX/3CRV ratio in the metapool to save gas
        //    braxPerLpToken = ((brax3crvHeld * 1e18) / stakingToken.totalSupply()) / 2;
        // }

        // Uniswap V2
        // ============================================
        {
            uint256 totalBraxReserves;
            (uint256 reserve0, uint256 reserve1, ) = (stakingToken.getReserves());
            if (braxIsToken0) totalBraxReserves = reserve0;
            else totalBraxReserves = reserve1;

            braxPerLpToken = (totalBraxReserves * 1e18) / stakingToken.totalSupply();
        }

        // Vesper
        // ============================================
        // braxPerLpToken = stakingToken.pricePerShare();

        return braxPerLpToken;
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
        for (uint256 i = 0; i < lockedStakes[account].length; i++) {
            LockedStake memory thisStake = lockedStakes[account][i];
            uint256 lockMultiplier = thisStake.lockMultiplier;

            // If the lock is expired
            if (thisStake.endingTimestamp <= block.timestamp) {
                // If the lock expired in the time since the last claim, the weight needs to be proportionately averaged this time
                if (lastRewardClaimTime[account] < thisStake.endingTimestamp){
                    uint256 timeBeforeExpiry = thisStake.endingTimestamp - lastRewardClaimTime[account];
                    uint256 timeAfterExpiry = block.timestamp - thisStake.endingTimestamp;

                    // Get the weighted-average lockMultiplier
                    uint256 numerator = (lockMultiplier * timeBeforeExpiry) + (MULTIPLIER_PRECISION * timeAfterExpiry);
                    lockMultiplier = numerator / (timeBeforeExpiry + timeAfterExpiry);
                }
                // Otherwise, it needs to just be 1x
                else {
                    lockMultiplier = MULTIPLIER_PRECISION;
                }
            }

            uint256 liquidity = thisStake.liquidity;
            uint256 combinedBoostedAmount = (liquidity * (lockMultiplier + midpointVebxsMultiplier)) / MULTIPLIER_PRECISION;
            newCombinedWeight = newCombinedWeight + combinedBoostedAmount;
        }
    }

    // ------ LOCK RELATED ------

    // All the locked stakes for a given account
    function lockedStakesOf(address account) external view returns (LockedStake[] memory) {
        return lockedStakes[account];
    }

    // Returns the length of the locked stakes for a given account
    function lockedStakesOfLength(address account) external view returns (uint256) {
        return lockedStakes[account].length;
    }

    // // All the locked stakes for a given account [old-school method]
    // function lockedStakesOfMultiArr(address account) external view returns (
    //     bytes32[] memory kekIds,
    //     uint256[] memory startTimestamps,
    //     uint256[] memory liquidities,
    //     uint256[] memory endingTimestamps,
    //     uint256[] memory lockMultipliers
    // ) {
    //     for (uint256 i = 0; i < lockedStakes[account].length; i++){ 
    //         LockedStake memory thisStake = lockedStakes[account][i];
    //         kekIds[i] = thisStake.kekId;
    //         startTimestamps[i] = thisStake.startTimestamp;
    //         liquidities[i] = thisStake.liquidity;
    //         endingTimestamps[i] = thisStake.endingTimestamp;
    //         lockMultipliers[i] = thisStake.lockMultiplier;
    //     }
    // }

    /* =============== MUTATIVE FUNCTIONS =============== */

    // ------ STAKING ------

    function _getStake(address stakerAddress, bytes32 kekId) internal view returns (LockedStake memory lockedStake, uint256 arrIdx) {
        for (uint256 i = 0; i < lockedStakes[stakerAddress].length; i++){ 
            if (kekId == lockedStakes[stakerAddress][i].kekId){
                lockedStake = lockedStakes[stakerAddress][i];
                arrIdx = i;
                break;
            }
        }
        require(lockedStake.kekId == kekId, "Stake not found");
        
    }

    // Add additional LPs to an existing locked stake
    function lockAdditional(bytes32 kekId, uint256 addlLiq) updateRewardAndBalance(msg.sender, true) public {
        // Get the stake and its index
        (LockedStake memory thisStake, uint256 theArrayIndex) = _getStake(msg.sender, kekId);

        // Calculate the new amount
        uint256 newAmt = thisStake.liquidity + addlLiq;

        // Checks
        require(addlLiq >= 0, "Must be nonzero");

        // Pull the tokens from the sender
        TransferHelper.safeTransferFrom(address(stakingToken), msg.sender, address(this), addlLiq);

        // Update the stake
        lockedStakes[msg.sender][theArrayIndex] = LockedStake(
            kekId,
            thisStake.startTimestamp,
            newAmt,
            thisStake.endingTimestamp,
            thisStake.lockMultiplier
        );

        // Update liquidities
        _totalLiquidityLocked += addlLiq;
        _lockedLiquidity[msg.sender] += addlLiq;
        {
            address theProxy = getProxyFor(msg.sender);
            if (theProxy != address(0)) proxyLpBalances[theProxy] += addlLiq;
        }

        // Need to call to update the combined weights
        _updateRewardAndBalance(msg.sender, false);
    }

    // Two different stake functions are needed because of delegateCall and msg.sender issues (important for migration)
    function stakeLocked(uint256 liquidity, uint256 secs) nonReentrant external {
        _stakeLocked(msg.sender, msg.sender, liquidity, secs, block.timestamp);
    }

    function _stakeLockedInternalLogic(
        address sourceAddress,
        uint256 liquidity
    ) internal virtual {
        revert("Need _stakeLockedInternalLogic logic");
    }

    // If this were not internal, and sourceAddress had an infinite approve, this could be exploitable
    // (pull funds from sourceAddress and stake for an arbitrary stakerAddress)
    function _stakeLocked(
        address stakerAddress,
        address sourceAddress,
        uint256 liquidity,
        uint256 secs,
        uint256 startTimestamp
    ) internal updateRewardAndBalance(stakerAddress, true) {
        require(stakingPaused == false || validMigrators[msg.sender] == true, "Staking paused or in migration");
        require(secs >= lockTimeMin, "Minimum stake time not met");
        require(secs <= lockTimeForMaxMultiplier,"Trying to lock for too long");

        // Pull in the required token(s)
        // Varies per farm
        TransferHelper.safeTransferFrom(address(stakingToken), sourceAddress, address(this), liquidity);

        // Get the lock multiplier and kekId
        uint256 lockMultiplier = lockMultiplier(secs);
        bytes32 kekId = keccak256(abi.encodePacked(stakerAddress, startTimestamp, liquidity, _lockedLiquidity[stakerAddress]));
        
        // Create the locked stake
        lockedStakes[stakerAddress].push(LockedStake(
            kekId,
            startTimestamp,
            liquidity,
            startTimestamp + secs,
            lockMultiplier
        ));

        // Update liquidities
        _totalLiquidityLocked += liquidity;
        _lockedLiquidity[stakerAddress] += liquidity;
        {
            address theProxy = getProxyFor(stakerAddress);
            if (theProxy != address(0)) proxyLpBalances[theProxy] += liquidity;
        }
        
        // Need to call again to make sure everything is correct
        _updateRewardAndBalance(stakerAddress, false);

        emit StakeLocked(stakerAddress, liquidity, secs, kekId, sourceAddress);
    }

    // ------ WITHDRAWING ------

    // Two different withdrawLocked functions are needed because of delegateCall and msg.sender issues (important for migration)
    function withdrawLocked(bytes32 kekId, address destinationAddress) nonReentrant external {
        require(withdrawalsPaused == false, "Withdrawals paused");
        _withdrawLocked(msg.sender, destinationAddress, kekId);
    }

    // No withdrawer == msg.sender check needed since this is only internally callable and the checks are done in the wrapper
    // functions like migratorWithdrawLocked() and withdrawLocked()
    function _withdrawLocked(
        address stakerAddress,
        address destinationAddress,
        bytes32 kekId
    ) internal {
        // Collect rewards first and then update the balances
        _getReward(stakerAddress, destinationAddress);

        // Get the stake and its index
        (LockedStake memory thisStake, uint256 theArrayIndex) = _getStake(stakerAddress, kekId);
        require(block.timestamp >= thisStake.endingTimestamp || stakesUnlocked == true || validMigrators[msg.sender] == true, "Stake is still locked!");
        uint256 liquidity = thisStake.liquidity;

        if (liquidity > 0) {
            // Update liquidities
            _totalLiquidityLocked = _totalLiquidityLocked - liquidity;
            _lockedLiquidity[stakerAddress] = _lockedLiquidity[stakerAddress] - liquidity;
            {
                address theProxy = getProxyFor(stakerAddress);
                if (theProxy != address(0)) proxyLpBalances[theProxy] -= liquidity;
            }

            // Remove the stake from the array
            delete lockedStakes[stakerAddress][theArrayIndex];

            // Give the tokens to the destinationAddress
            // Should throw if insufficient balance
            stakingToken.transfer(destinationAddress, liquidity);

            // Need to call again to make sure everything is correct
            _updateRewardAndBalance(stakerAddress, false);

            emit WithdrawLocked(stakerAddress, liquidity, kekId, destinationAddress);
        }
    }


    function _getRewardExtraLogic(address rewardee, address destinationAddress) internal override {
        // Do nothing
    }

     /* ========== RESTRICTED FUNCTIONS - Curator / migrator callable ========== */

    // Migrator can stake for someone else (they won't be able to withdraw it back though, only stakerAddress can). 
    function migratorStakeLockedFor(address stakerAddress, uint256 amount, uint256 secs, uint256 startTimestamp) external isMigrating {
        require(stakerAllowedMigrators[stakerAddress][msg.sender] && validMigrators[msg.sender], "Mig. invalid or unapproved");
        _stakeLocked(stakerAddress, msg.sender, amount, secs, startTimestamp);
    }

    // Used for migrations
    function migratorWithdrawLocked(address stakerAddress, bytes32 kekId) external isMigrating {
        require(stakerAllowedMigrators[stakerAddress][msg.sender] && validMigrators[msg.sender], "Mig. invalid or unapproved");
        _withdrawLocked(stakerAddress, msg.sender, kekId);
    }
    
    /* ========== RESTRICTED FUNCTIONS - Owner or timelock only ========== */

    // Inherited...

    /* ========== EVENTS ========== */

    event StakeLocked(address indexed user, uint256 amount, uint256 secs, bytes32 kekId, address sourceAddress);
    event WithdrawLocked(address indexed user, uint256 liquidity, bytes32 kekId, address destinationAddress);
}

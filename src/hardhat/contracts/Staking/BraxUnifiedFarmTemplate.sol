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
// ====================== BraxUnifiedFarmTemplate =====================
// ====================================================================
// Brax Finance: https://github.com/BraxFinance
// Based off of FRAX: https://github.com/FraxFinance

// Migratable Farming contract that accounts for veBXS
// Overrideable for UniV3, ERC20s, etc
// New for V2
//      - Multiple reward tokens possible
//      - Can add to existing locked stakes
//      - Contract is aware of proxied veBXS
//      - veBXS multiplier formula changed
// Apes together strong

// Frax Finance: https://github.com/FraxFinance

// FRAX Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna

// FRAX Reviewer(s) / Contributor(s)
// Jason Huan: https://github.com/jasonhuan
// Sam Kazemian: https://github.com/samkazemian
// Dennis: github.com/denett
// Sam Sun: https://github.com/samczsun

// Originally inspired by Synthetix.io, but heavily modified by the Frax team
// (Locked, veBXS, and UniV3 portions are new)
// https://raw.githubusercontent.com/Synthetixio/synthetix/develop/contracts/StakingRewards.sol

// BRAX Modification Author(s)
// mitche50: https://github.com/mitche50

import "../Math/Math.sol";
import "../Curve/IveBXS.sol";
import "../Curve/IBraxGaugeController.sol";
import "../Curve/IBraxGaugeBXSRewardsDistributor.sol";
import "../ERC20/ERC20.sol";
import '../Uniswap/TransferHelper.sol';
import "../ERC20/SafeERC20.sol";
import "../Utils/ReentrancyGuard.sol";
import "./Owned.sol";

contract BraxUnifiedFarmTemplate is Owned, ReentrancyGuard {
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    // Instances
    IveBXS private veBXS;
    
    // Brax related
    address internal braxAddress;
    bool internal braxIsToken0;
    uint256 public braxPerLPStored;

    // Constant for various precisions
    uint256 internal constant MULTIPLIER_PRECISION = 1e18;

    // Time tracking
    uint256 public periodFinish;
    uint256 public lastUpdateTime;

    // Lock time and multiplier settings
    uint256 public lockMaxMultiplier = uint256(3e18); // E18. 1x = e18
    uint256 public lockTimeForMaxMultiplier = 3 * 365 * 86400; // 3 years
    uint256 public lockTimeMin = 86400; // 1 * 86400  (1 day)

    // veBXS related
    uint256 public vebxsBoostScaleFactor = uint256(4e18); // E18. 4x = 4e18; 100 / scaleFactor = % vebxs supply needed for max boost
    uint256 public vebxsMaxMultiplier = uint256(2e18); // E18. 1x = 1e18
    uint256 public vebxsPerBraxForMaxBoost = uint256(2e18); // E18. 2e18 means 2 veBXS must be held by the staker per 1 BRAX
    mapping(address => uint256) internal _vebxsMultiplierStored;
    mapping(address => bool) internal validVebxsProxies;
    mapping(address => mapping(address => bool)) internal proxyAllowedStakers;

    // Reward addresses, gauge addresses, reward rates, and reward managers
    mapping(address => address) public rewardManagers; // token addr -> manager addr
    address[] internal rewardTokens;
    address[] internal gaugeControllers;
    address[] internal rewardDistributors;
    uint256[] internal rewardRatesManual;
    mapping(address => uint256) public rewardTokenAddrToIdx; // token addr -> token index
    
    // Reward period
    uint256 public constant rewardsDuration = 604800; // 7 * 86400  (7 days)

    // Reward tracking
    uint256[] private rewardsPerTokenStored;
    mapping(address => mapping(uint256 => uint256)) private userRewardsPerTokenPaid; // staker addr -> token id -> paid amount
    mapping(address => mapping(uint256 => uint256)) private rewards; // staker addr -> token id -> reward amount
    mapping(address => uint256) internal lastRewardClaimTime; // staker addr -> timestamp
    
    // Gauge tracking
    uint256[] private lastGaugeRelativeWeights;
    uint256[] private lastGaugeTimeTotals;

    // Balance tracking
    uint256 internal _totalLiquidityLocked;
    uint256 internal _totalCombinedWeight;
    mapping(address => uint256) internal _lockedLiquidity;
    mapping(address => uint256) internal _combinedWeights;
    mapping(address => uint256) public proxyLpBalances; // Keeps track of LP balances proxy-wide. Needed to make sure the proxy boost is kept in line

    // List of valid migrators (set by governance)
    mapping(address => bool) internal validMigrators;

    // Stakers set which migrator(s) they want to use
    mapping(address => mapping(address => bool)) internal stakerAllowedMigrators;
    mapping(address => address) public stakerDesignatedProxies; // Keep public so users can see on the frontend if they have a proxy

    // Admin booleans for emergencies, migrations, and overrides
    bool public stakesUnlocked; // Release locked stakes in case of emergency
    bool internal migrationsOn; // Used for migrations. Prevents new stakes, but allows LP and reward withdrawals
    bool internal withdrawalsPaused; // For emergencies
    bool internal rewardsCollectionPaused; // For emergencies
    bool internal stakingPaused; // For emergencies

    /* ========== STRUCTS ========== */
    // In children...


    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require(msg.sender == owner || msg.sender == address(0), "Not owner or timelock");
        _;
    }

    modifier onlyTknMgrs(address rewardTokenAddress) {
        require(msg.sender == owner || isTokenManagerFor(msg.sender, rewardTokenAddress), "Not owner or tkn mgr");
        _;
    }

    modifier isMigrating() {
        require(migrationsOn == true, "Not in migration");
        _;
    }

    modifier updateRewardAndBalance(address account, bool syncToo) {
        _updateRewardAndBalance(account, syncToo);
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (
        address _owner,
        address[] memory _rewardTokens,
        address[] memory _rewardManagers,
        uint256[] memory _rewardRatesManual,
        address[] memory _gaugeControllers,
        address[] memory _rewardDistributors,
        address genVeBXS,
        address genBrax
    ) Owned(_owner) {

        // Address arrays
        rewardTokens = _rewardTokens;
        gaugeControllers = _gaugeControllers;
        rewardDistributors = _rewardDistributors;
        rewardRatesManual = _rewardRatesManual;
        veBXS = IveBXS(genVeBXS);
        braxAddress = genBrax;

        for (uint256 i = 0; i < _rewardTokens.length; i++){ 
            // For fast token address -> token ID lookups later
            rewardTokenAddrToIdx[_rewardTokens[i]] = i;

            // Initialize the stored rewards
            rewardsPerTokenStored.push(0);

            // Initialize the reward managers
            rewardManagers[_rewardTokens[i]] = _rewardManagers[i];

            // Push in empty relative weights to initialize the array
            lastGaugeRelativeWeights.push(0);

            // Push in empty time totals to initialize the array
            lastGaugeTimeTotals.push(0);
        }

        // Other booleans
        stakesUnlocked = false;

        // Initialization
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
    }

    /* ============= VIEWS ============= */

    // ------ REWARD RELATED ------

    // See if the callerAddr is a manager for the reward token 
    function isTokenManagerFor(address callerAddr, address rewardTokenAddr) public view returns (bool){
        if (callerAddr == owner) return true; // Contract owner
        else if (rewardManagers[rewardTokenAddr] == callerAddr) return true; // Reward manager
        return false; 
    }

    // All the reward tokens
    function getAllRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    // Last time the reward was applicable
    function lastTimeRewardApplicable() internal view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardRates(uint256 tokenIdx) public view returns (uint256 rwdRate) {
        address gaugeControllerAddress = gaugeControllers[tokenIdx];
        if (gaugeControllerAddress != address(0)) {
            rwdRate = (IBraxGaugeController(gaugeControllerAddress).global_emission_rate() * lastGaugeRelativeWeights[tokenIdx]) / 1e18;
        }
        else {
            rwdRate = rewardRatesManual[tokenIdx];
        }
    }

    // Amount of reward tokens per LP token / liquidity unit
    function rewardsPerToken() public view returns (uint256[] memory newRewardsPerTokenStored) {
        if (_totalLiquidityLocked == 0 || _totalCombinedWeight == 0) {
            return rewardsPerTokenStored;
        }
        else {
            newRewardsPerTokenStored = new uint256[](rewardTokens.length);
            for (uint256 i = 0; i < rewardsPerTokenStored.length; i++){ 
                newRewardsPerTokenStored[i] = rewardsPerTokenStored[i] + (
                    ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRates(i) * 1e18) / _totalCombinedWeight
                );
            }
            return newRewardsPerTokenStored;
        }
    }

    // Amount of reward tokens an account has earned / accrued
    // Note: In the edge-case of one of the account's stake expiring since the last claim, this will
    // return a slightly inflated number
    function earned(address account) public view returns (uint256[] memory newEarned) {
        uint256[] memory rewardArr = rewardsPerToken();
        newEarned = new uint256[](rewardTokens.length);

        if (_combinedWeights[account] > 0){
            for (uint256 i = 0; i < rewardTokens.length; i++){ 
                newEarned[i] = ((_combinedWeights[account] * (rewardArr[i] - userRewardsPerTokenPaid[account][i])) / 1e18)
                                + rewards[account][i];
            }
        }
    }

    // Total reward tokens emitted in the given period
    function getRewardForDuration() external view returns (uint256[] memory rewardsPerDurationArr) {
        rewardsPerDurationArr = new uint256[](rewardRatesManual.length);

        for (uint256 i = 0; i < rewardRatesManual.length; i++){ 
            rewardsPerDurationArr[i] = rewardRates(i) * rewardsDuration;
        }
    }


    // ------ LIQUIDITY AND WEIGHTS ------

    // User locked liquidity / LP tokens
    function totalLiquidityLocked() external view returns (uint256) {
        return _totalLiquidityLocked;
    }

    // Total locked liquidity / LP tokens
    function lockedLiquidityOf(address account) external view returns (uint256) {
        return _lockedLiquidity[account];
    }

    // Total combined weight
    function totalCombinedWeight() external view returns (uint256) {
        return _totalCombinedWeight;
    }

    // Total 'balance' used for calculating the percent of the pool the account owns
    // Takes into account the locked stake time multiplier and veBXS multiplier
    function combinedWeightOf(address account) external view returns (uint256) {
        return _combinedWeights[account];
    }

    // Calculated the combined weight for an account
    function calcCurCombinedWeight(address account) public virtual view 
        returns (
            uint256 oldCombinedWeight,
            uint256 newVebxsMultiplier,
            uint256 newCombinedWeight
        )
    {
        revert("Need cCCW logic");
    }

    // ------ LOCK RELATED ------

    // Multiplier amount, given the length of the lock
    function lockMultiplier(uint256 secs) public view returns (uint256) {
        return Math.min(
            lockMaxMultiplier,
            uint256(MULTIPLIER_PRECISION) + (
                (secs * (lockMaxMultiplier - MULTIPLIER_PRECISION)) / lockTimeForMaxMultiplier
            )
        ) ;
    }

    // ------ BRAX RELATED ------

    function userStakedBrax(address account) public view returns (uint256) {
        return (braxPerLPStored * _lockedLiquidity[account]) / MULTIPLIER_PRECISION;
    }

    function proxyStakedBrax(address proxyAddress) public view returns (uint256) {
        return (braxPerLPStored * proxyLpBalances[proxyAddress]) / MULTIPLIER_PRECISION;
    }

    // Max LP that can get max veBXS boosted for a given address at its current veBXS balance
    function maxLPForMaxBoost(address account) external view returns (uint256) {
        return (veBXS.balanceOf(account) * MULTIPLIER_PRECISION * MULTIPLIER_PRECISION) / (vebxsPerBraxForMaxBoost * braxPerLPStored);
    }

    // Meant to be overridden
    function braxPerLPToken() public virtual view returns (uint256) {
        revert("Need fPLPT logic");
    }

    // ------ veBXS RELATED ------

    function minVeBXSForMaxBoost(address account) public view returns (uint256) {
        return (userStakedBrax(account) * vebxsPerBraxForMaxBoost) / MULTIPLIER_PRECISION;
    }

    function minVeBXSForMaxBoostProxy(address proxyAddress) public view returns (uint256) {
        return (proxyStakedBrax(proxyAddress) * vebxsPerBraxForMaxBoost) / MULTIPLIER_PRECISION;
    }

    function getProxyFor(address addr) public view returns (address){
        if (validVebxsProxies[addr]) {
            // If addr itself is a proxy, return that.
            // If it farms itself directly, it should use the shared LP tally in proxyStakedBrax
            return addr;
        }
        else {
            // Otherwise, return the proxy, or address(0)
            return stakerDesignatedProxies[addr];
        }
    }

    function veBXSMultiplier(address account) public view returns (uint256 vebxsMultiplier) {
        // Use either the user's or their proxy's veBXS balance
        uint256 vebxsBalToUse = 0;
        address theProxy = getProxyFor(account);
        vebxsBalToUse = (theProxy == address(0)) ? veBXS.balanceOf(account) : veBXS.balanceOf(theProxy);

        // First option based on fraction of total veBXS supply, with an added scale factor
        uint256 multOptn1 = (vebxsBalToUse * vebxsMaxMultiplier * vebxsBoostScaleFactor) 
                            / (veBXS.totalSupply() * MULTIPLIER_PRECISION);
        
        // Second based on old method, where the amount of BRAX staked comes into play
        uint256 multOptn2;
        {
            uint256 veBXSNeededForMaxBoost;

            // Need to use proxy-wide BRAX balance if applicable, to prevent exploiting
            veBXSNeededForMaxBoost = (theProxy == address(0)) ? minVeBXSForMaxBoost(account) : minVeBXSForMaxBoostProxy(theProxy);

            if (veBXSNeededForMaxBoost > 0){ 
                uint256 userVebxsFraction = (vebxsBalToUse * MULTIPLIER_PRECISION) / veBXSNeededForMaxBoost;
                
                multOptn2 = (userVebxsFraction * vebxsMaxMultiplier) / MULTIPLIER_PRECISION;
            }
            else multOptn2 = 0; // This will happen with the first stake, when userStakedBrax is 0
        }

        // Select the higher of the two
        vebxsMultiplier = (multOptn1 > multOptn2 ? multOptn1 : multOptn2);

        // Cap the boost to the vebxsMaxMultiplier
        if (vebxsMultiplier > vebxsMaxMultiplier) vebxsMultiplier = vebxsMaxMultiplier;
    }

    /* =============== MUTATIVE FUNCTIONS =============== */

    // ------ MIGRATIONS ------

    // Staker can allow a migrator 
    function stakerToggleMigrator(address migratorAddress) external {
        require(validMigrators[migratorAddress], "Invalid migrator address");
        stakerAllowedMigrators[msg.sender][migratorAddress] = !stakerAllowedMigrators[msg.sender][migratorAddress]; 
    }

    // Proxy can allow a staker to use their veBXS balance (the staker will have to reciprocally toggle them too)
    // Must come before stakerSetVeBXSProxy
    function proxyToggleStaker(address stakerAddress) external {
        require(validVebxsProxies[msg.sender], "Invalid proxy");
        proxyAllowedStakers[msg.sender][stakerAddress] = !proxyAllowedStakers[msg.sender][stakerAddress]; 

        // Disable the staker's set proxy if it was the toggler and is currently on
        if (stakerDesignatedProxies[stakerAddress] == msg.sender){
            stakerDesignatedProxies[stakerAddress] = address(0); 

            // Remove the LP as well
            proxyLpBalances[msg.sender] -= _lockedLiquidity[stakerAddress];
        }
    }

    // Staker can allow a veBXS proxy (the proxy will have to toggle them first)
    function stakerSetVeBXSProxy(address proxyAddress) external {
        require(validVebxsProxies[proxyAddress], "Invalid proxy");
        require(proxyAllowedStakers[proxyAddress][msg.sender], "Proxy has not allowed you yet");
        stakerDesignatedProxies[msg.sender] = proxyAddress; 

        // Add the the LP as well
        proxyLpBalances[proxyAddress] += _lockedLiquidity[msg.sender];
    }

    // ------ STAKING ------
    // In children...


    // ------ WITHDRAWING ------
    // In children...


    // ------ REWARDS SYNCING ------

    function _updateRewardAndBalance(address account, bool syncToo) internal {
        // Need to retro-adjust some things if the period hasn't been renewed, then start a new one
        if (syncToo){
            sync();
        }
        
        if (account != address(0)) {
            // To keep the math correct, the user's combined weight must be recomputed to account for their
            // ever-changing veBXS balance.
            (   
                uint256 oldCombinedWeight,
                uint256 newVebxsMultiplier,
                uint256 newCombinedWeight
            ) = calcCurCombinedWeight(account);

            // Calculate the earnings first
            _syncEarned(account);

            // Update the user's stored veBXS multipliers
            _vebxsMultiplierStored[account] = newVebxsMultiplier;

            // Update the user's and the global combined weights
            if (newCombinedWeight >= oldCombinedWeight) {
                uint256 weightDiff = newCombinedWeight - oldCombinedWeight;
                _totalCombinedWeight = _totalCombinedWeight + weightDiff;
                _combinedWeights[account] = oldCombinedWeight + weightDiff;
            } else {
                uint256 weightDiff = oldCombinedWeight - newCombinedWeight;
                _totalCombinedWeight = _totalCombinedWeight - weightDiff;
                _combinedWeights[account] = oldCombinedWeight - weightDiff;
            }

        }
    }

    function _syncEarned(address account) internal {
        if (account != address(0)) {
            // Calculate the earnings
            uint256[] memory earnedArr = earned(account);

            // Update the rewards array
            for (uint256 i = 0; i < earnedArr.length; i++){ 
                rewards[account][i] = earnedArr[i];
            }

            // Update the rewards paid array
            for (uint256 i = 0; i < earnedArr.length; i++){ 
                userRewardsPerTokenPaid[account][i] = rewardsPerTokenStored[i];
            }
        }
    }


    // ------ REWARDS CLAIMING ------

    function _getRewardExtraLogic(address rewardee, address destinationAddress) internal virtual {
        revert("Need gREL logic");
    }

    // Two different getReward functions are needed because of delegateCall and msg.sender issues
    function getReward(address destinationAddress) external nonReentrant returns (uint256[] memory) {
        require(rewardsCollectionPaused == false, "Rewards collection paused");
        return _getReward(msg.sender, destinationAddress);
    }

    // No withdrawer == msg.sender check needed since this is only internally callable
    function _getReward(address rewardee, address destinationAddress) internal updateRewardAndBalance(rewardee, true) returns (uint256[] memory rewardsBefore) {
        // Update the rewards array and distribute rewards
        rewardsBefore = new uint256[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++){ 
            rewardsBefore[i] = rewards[rewardee][i];
            rewards[rewardee][i] = 0;
            if (rewardsBefore[i] > 0) TransferHelper.safeTransfer(rewardTokens[i], destinationAddress, rewardsBefore[i]);
        }

        // Handle additional reward logic
        _getRewardExtraLogic(rewardee, destinationAddress);

        // Update the last reward claim time
        lastRewardClaimTime[rewardee] = block.timestamp;
    }


    // ------ FARM SYNCING ------

    // If the period expired, renew it
    function retroCatchUp() internal {
        // Pull in rewards from the rewards distributor, if applicable
        for (uint256 i = 0; i < rewardDistributors.length; i++){ 
            address rewardDistributorAddress = rewardDistributors[i];
            if (rewardDistributorAddress != address(0)) {
                IBraxGaugeBXSRewardsDistributor(rewardDistributorAddress).distributeReward(address(this));
            }
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 numPeriodsElapsed = uint256(block.timestamp - periodFinish) / rewardsDuration; // Floor division to the nearest period
        
        // Make sure there are enough tokens to renew the reward period
        for (uint256 i = 0; i < rewardTokens.length; i++){ 
            require((rewardRates(i) * rewardsDuration * (numPeriodsElapsed + 1)) <= ERC20(rewardTokens[i]).balanceOf(address(this)), string(abi.encodePacked("Not enough reward tokens available: ", rewardTokens[i])) );
        }
        
        // uint256 oldLastUpdateTime = lastUpdateTime;
        // uint256 newLastUpdateTime = block.timestamp;

        // lastUpdateTime = periodFinish;
        periodFinish = periodFinish + ((numPeriodsElapsed + 1) * rewardsDuration);

        // Update the rewards and time
        _updateStoredRewardsAndTime();

        // Update the braxPerLPStored
        braxPerLPStored = braxPerLPToken();
    }

    function _updateStoredRewardsAndTime() internal {
        // Get the rewards
        uint256[] memory tempRewardsPerToken = rewardsPerToken();

        // Update the rewardsPerTokenStored
        for (uint256 i = 0; i < rewardsPerTokenStored.length; i++){ 
            rewardsPerTokenStored[i] = tempRewardsPerToken[i];
        }

        // Update the last stored time
        lastUpdateTime = lastTimeRewardApplicable();
    }

    function syncGaugeWeights(bool forceUpdate) public {
        // Loop through the gauge controllers
        for (uint256 i = 0; i < gaugeControllers.length; i++){ 
            address gaugeControllerAddress = gaugeControllers[i];
            if (gaugeControllerAddress != address(0)) {
                if (forceUpdate || (block.timestamp > lastGaugeTimeTotals[i])){
                    // Update the gauge_relative_weight
                    lastGaugeRelativeWeights[i] = IBraxGaugeController(gaugeControllerAddress).gauge_relative_weight_write(address(this), block.timestamp);
                    lastGaugeTimeTotals[i] = IBraxGaugeController(gaugeControllerAddress).time_total();
                }
            }
        }
    }

    function sync() public {
        // Sync the gauge weight, if applicable
        syncGaugeWeights(false);

        // Update the braxPerLPStored
        braxPerLPStored = braxPerLPToken();

        if (block.timestamp >= periodFinish) {
            retroCatchUp();
        }
        else {
            _updateStoredRewardsAndTime();
        }
    }

    /* ========== RESTRICTED FUNCTIONS - Curator / migrator callable ========== */
    
    // ------ FARM SYNCING ------
    // In children...

    // ------ PAUSES ------

    function setPauses(
        bool _stakingPaused,
        bool _withdrawalsPaused,
        bool _rewardsCollectionPaused
    ) external onlyByOwnGov {
        stakingPaused = _stakingPaused;
        withdrawalsPaused = _withdrawalsPaused;
        rewardsCollectionPaused = _rewardsCollectionPaused;
    }

    /* ========== RESTRICTED FUNCTIONS - Owner or timelock only ========== */
    
    function unlockStakes() external onlyByOwnGov {
        stakesUnlocked = !stakesUnlocked;
    }

    function toggleMigrations() external onlyByOwnGov {
        migrationsOn = !migrationsOn;
    }

    // Adds supported migrator address
    function toggleMigrator(address migratorAddress) external onlyByOwnGov {
        validMigrators[migratorAddress] = !validMigrators[migratorAddress];
    }

    // Adds a valid veBXS proxy address
    function toggleValidVeBXSProxy(address _proxyAddr) external onlyByOwnGov {
        validVebxsProxies[_proxyAddr] = !validVebxsProxies[_proxyAddr];
    }

    // Added to support recovering LP Rewards and other mistaken tokens from other systems to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyTknMgrs(tokenAddress) {
        // Check if the desired token is a reward token
        bool isRewardToken = false;
        for (uint256 i = 0; i < rewardTokens.length; i++){ 
            if (rewardTokens[i] == tokenAddress) {
                isRewardToken = true;
                break;
            }
        }

        // Only the reward managers can take back their reward tokens
        // Also, other tokens, like the staking token, airdrops, or accidental deposits, can be withdrawn by the owner
        if (
                (isRewardToken && rewardManagers[tokenAddress] == msg.sender)
                || (!isRewardToken && (msg.sender == owner))
            ) {
            TransferHelper.safeTransfer(tokenAddress, msg.sender, tokenAmount);
            return;
        }
        // If none of the above conditions are true
        else {
            revert("No valid tokens to recover");
        }
    }

    function setMiscVariables(
        uint256[6] memory _miscVars
        // [0]: uint256 _lockMaxMultiplier, 
        // [1] uint256 _vebxsMaxMultiplier, 
        // [2] uint256 _vebxsPerBraxForMaxBoost,
        // [3] uint256 _vebxsBoostScaleFactor,
        // [4] uint256 _lockTimeForMaxMultiplier,
        // [5] uint256 _lockTimeMin
    ) external onlyByOwnGov {
        require(_miscVars[0] >= MULTIPLIER_PRECISION, "Must be >= MUL PREC");
        require((_miscVars[1] >= 0) && (_miscVars[2] >= 0) && (_miscVars[3] >= 0), "Must be >= 0");
        require((_miscVars[4] >= 1) && (_miscVars[5] >= 1), "Must be >= 1");

        lockMaxMultiplier = _miscVars[0];
        vebxsMaxMultiplier = _miscVars[1];
        vebxsPerBraxForMaxBoost = _miscVars[2];
        vebxsBoostScaleFactor = _miscVars[3];
        lockTimeForMaxMultiplier = _miscVars[4];
        lockTimeMin = _miscVars[5];
    }

    // The owner or the reward token managers can set reward rates 
    function setRewardVars(address rewardTokenAddress, uint256 _newRate, address _gaugeControllerAddress, address _rewardsDistributorAddress) external onlyTknMgrs(rewardTokenAddress) {
        rewardRatesManual[rewardTokenAddrToIdx[rewardTokenAddress]] = _newRate;
        gaugeControllers[rewardTokenAddrToIdx[rewardTokenAddress]] = _gaugeControllerAddress;
        rewardDistributors[rewardTokenAddrToIdx[rewardTokenAddress]] = _rewardsDistributorAddress;
    }

    // The owner or the reward token managers can change managers
    function changeTokenManager(address rewardTokenAddress, address newManagerAddress) external onlyTknMgrs(rewardTokenAddress) {
        rewardManagers[rewardTokenAddress] = newManagerAddress;
    }

    /* ========== A CHICKEN ========== */
    //
    //         ,~.
    //      ,-'__ `-,
    //     {,-'  `. }              ,')
    //    ,( a )   `-.__         ,',')~,
    //   <=.) (         `-.__,==' ' ' '}
    //     (   )                      /)
    //      `-'\   ,                    )
    //          |  \        `~.        /
    //          \   `._        \      /
    //           \     `._____,'    ,'
    //            `-.             ,'
    //               `-._     _,-'
    //                   77jj'
    //                  //_||
    //               __//--'/`
    //             ,--'/`  '
    //
    // [hjw] https://textart.io/art/vw6Sa3iwqIRGkZsN1BC2vweF/chicken
}

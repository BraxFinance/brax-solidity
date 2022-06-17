// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

// ======================================================================
// |     ____  ____  ___   _  __    _______                             | 
// |    / __ )/ __ \/   | | |/ /   / ____(____  ____ _____  ________    | 
// |   / __  / /_/ / /| | |   /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / /_/ / _, _/ ___ |/   |   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_____/_/ |_/_/  |_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                    |
// ======================================================================
// =========================== BraxAMOMinter ============================
// ======================================================================
// globalCollateralValue() in Brax.sol is gassy because of the loop and all of the AMOs attached to it. 
// This minter would be single mint point for all of the AMOs, and would track the collatBtcBalance with a
// state variable after any mint occurs, or manually with a sync() call
// Brax Finance: https://github.com/BraxFinance

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna

// Reviewer(s) / Contributor(s)
// Jason Huan: https://github.com/jasonhuan
// Sam Kazemian: https://github.com/samkazemian
// Dennis: github.com/denett
// Hameed
// Andrew Mitchell: https://github.com/mitche50

import "../Math/SafeMath.sol";
import "./IBrax.sol";
import "../BXS/IBxs.sol";
import "../Brax/Pools/BraxPoolV3.sol";
import "../ERC20/ERC20.sol";
import "../Staking/Owned.sol";
import '../Uniswap/TransferHelper.sol';
import '../Misc_AMOs/IAMO.sol';

contract BraxAMOMinter is Owned {
    // SafeMath automatically included in Solidity >= 8.0.0

    /* ========== STATE VARIABLES ========== */

    // Core
    IBrax public BRAX;
    IBxs public BXS;
    ERC20 public collateralToken;
    BraxPoolV3 public pool;
    address public timelockAddress;
    address public custodianAddress;

    // Collateral related
    address public collateralAddress;
    uint256 public colIdx;

    // AMO addresses
    address[] public amosArray;
    mapping(address => bool) public amos; // Mapping is also used for faster verification

    // Price constants
    uint256 private constant PRICE_PRECISION = 1e8;

    // Max amount of collateral the contract can borrow from the BraxPool
    // Set to 250 BTC to match BRAX 10m
    int256 public collatBorrowCap = int256(250e8);

    // Max amount of BRAX and BXS this contract can mint
    // Set to 2500 BRAX to match FRAX 100m, BXS stays the same
    int256 public braxMintCap = int256(2500e18);
    int256 public bxsMintCap = int256(100000000e18);

    // Minimum collateral ratio needed for new BRAX minting
    uint256 public minCr = 81000000;

    // Brax mint balances
    mapping(address => int256) public braxMintBalances; // Amount of BRAX the contract minted, by AMO
    int256 public braxMintSum = 0; // Across all AMOs

    // Bxs mint balances
    mapping(address => int256) public bxsMintBalances; // Amount of BXS the contract minted, by AMO
    int256 public bxsMintSum = 0; // Across all AMOs

    // Collateral borrowed balances
    mapping(address => int256) public collatBorrowedBalances; // Amount of collateral the contract borrowed, by AMO
    int256 public collatBorrowedSum = 0; // Across all AMOs

    // BRAX balance related
    uint256 public braxBtcBalanceStored = 0;

    // Collateral balance related
    uint256 public missingDecimals;
    uint256 public collatBtcBalanceStored = 0;

    // AMO balance corrections
    mapping(address => int256[2]) public correctionOffsetsAmos;
    // [amoAddress][0] = AMO's braxValE18
    // [amoAddress][1] = AMO's collatValE18

    /* ========== CONSTRUCTOR ========== */

    constructor (
        address genBraxAddress,
        address genBxsAddress,
        address genOwnerAddress,
        address genCustodianAddress,
        address genTimelockAddress,
        address genCollateralAddress,
        address genPoolAddress
    ) Owned(genOwnerAddress) {
        BRAX = IBrax(genBraxAddress);
        BXS = IBxs(genBxsAddress);

        custodianAddress = genCustodianAddress;
        timelockAddress = genTimelockAddress;

        // Pool related
        pool = BraxPoolV3(genPoolAddress);

        // Collateral related
        collateralAddress = genCollateralAddress;
        colIdx = pool.collateralAddrToIdx(genCollateralAddress);
        collateralToken = ERC20(genCollateralAddress);
        missingDecimals = uint(18) - collateralToken.decimals();
    }

    /* ========== MODIFIERS ========== */

    modifier onlyByGov() {
        require(msg.sender == timelockAddress, "Not timelock");
        _;
    }

    modifier onlyByOwnGov() {
        require(msg.sender == timelockAddress || msg.sender == owner, "Not owner or timelock");
        _;
    }

    modifier validAMO(address amoAddress) {
        require(amos[amoAddress], "Invalid AMO");
        _;
    }

    /* ========== VIEWS ========== */

    function collatBtcBalance() external view returns (uint256) {
        (, uint256 collatValE18) = btcBalances();
        return collatValE18;
    }

    function btcBalances() public view returns (uint256 braxValE18, uint256 collatValE18) {
        braxValE18 = braxBtcBalanceStored;
        collatValE18 = collatBtcBalanceStored;
    }

    function allAMOAddresses() external view returns (address[] memory) {
        return amosArray;
    }

    function allAMOsLength() external view returns (uint256) {
        return amosArray.length;
    }

    /**
     * @notice returns the global amount of BTC value in AMOs less what's been minted and borrowed
     * @dev braxBtcBalanceStored is the amount of BRAX value in AMOs
     * @dev braxMintSum is the amount of BRAX minted by the AMO
     * @dev collatBorrowedSum is the amount of borrowed collateral from the AMOs
     */
    function braxTrackedGlobal() external view returns (int256) {
        return int256(braxBtcBalanceStored) - braxMintSum - (collatBorrowedSum * int256(10 ** missingDecimals));
    }

    /**
     * @notice returns the BTC value in a specific AMO less what's been minted and borrowed
     * @param amoAddress address of the AMO
     * @return braxInAMO BTC value less what's been minted and borrowed
     */
    function braxTrackedAMO(address amoAddress) external view returns (int256) {
        (uint256 braxValE18, ) = IAMO(amoAddress).btcBalances();
        int256 braxValE18Corrected = int256(braxValE18) + correctionOffsetsAmos[amoAddress][0];
        return braxValE18Corrected - braxMintBalances[amoAddress] - ((collatBorrowedBalances[amoAddress]) * int256(10 ** missingDecimals));
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @notice Updates storage variable information
     */
    function syncBtcBalances() public {
        uint256 totalBraxValueD18 = 0;
        uint256 totalCollateralValueD18 = 0; 
        for (uint i = 0; i < amosArray.length; i++){ 
            // Exclude null addresses
            address amoAddress = amosArray[i];
            if (amoAddress != address(0)){
                (uint256 braxValE18, uint256 collatValE18) = IAMO(amoAddress).btcBalances();
                totalBraxValueD18 += uint256(int256(braxValE18) + correctionOffsetsAmos[amoAddress][0]);
                totalCollateralValueD18 += uint256(int256(collatValE18) + correctionOffsetsAmos[amoAddress][1]);
            }
        }
        braxBtcBalanceStored = totalBraxValueD18;
        collatBtcBalanceStored = totalCollateralValueD18;
    }

    /* ========== OWNER / GOVERNANCE FUNCTIONS ONLY ========== */
    // Only owner or timelock can call, to limit risk 

    // ------------------------------------------------------------------
    // ------------------------------ BRAX ------------------------------
    // ------------------------------------------------------------------

    /// @dev This contract is essentially marked as a 'pool' so it can call OnlyPools functions like poolMint and poolBurnFrom
    /// on the main BRAX contract
    function mintBraxForAMO(address destinationAmo, uint256 braxAmount) external onlyByOwnGov validAMO(destinationAmo) {
        int256 braxAmtI256 = int256(braxAmount);

        // Make sure you aren't minting more than the mint cap
        require((braxMintSum + braxAmtI256) <= braxMintCap, "Mint cap reached");
        braxMintBalances[destinationAmo] += braxAmtI256;
        braxMintSum += braxAmtI256;

        // Make sure the BRAX minting wouldn't push the CR down too much
        // This is also a sanity check for the int256 math
        uint256 currentCollateralE18 = BRAX.globalCollateralValue();
        uint256 curBraxSupply = BRAX.totalSupply();
        uint256 newBraxSupply = curBraxSupply + braxAmount;
        uint256 newCr = (currentCollateralE18 * PRICE_PRECISION) / newBraxSupply;
        require(newCr >= minCr, "CR would be too low");

        // Mint the BRAX to the AMO
        BRAX.poolMint(destinationAmo, braxAmount);

        // Sync
        syncBtcBalances();
    }

    function burnBraxFromAMO(uint256 braxAmount) external validAMO(msg.sender) {
        int256 braxAmtI256 = int256(braxAmount);

        // Burn first
        BRAX.poolBurnFrom(msg.sender, braxAmount);

        // Then update the balances
        braxMintBalances[msg.sender] -= braxAmtI256;
        braxMintSum -= braxAmtI256;

        // Sync
        syncBtcBalances();
    }

    // ------------------------------------------------------------------
    // ------------------------------- BXS ------------------------------
    // ------------------------------------------------------------------

    function mintBxsForAMO(address destinationAmo, uint256 bxsAmount) external onlyByOwnGov validAMO(destinationAmo) {
        int256 bxsAmtI256 = int256(bxsAmount);

        // Make sure you aren't minting more than the mint cap
        require((bxsMintSum + bxsAmtI256) <= bxsMintCap, "Mint cap reached");
        bxsMintBalances[destinationAmo] += bxsAmtI256;
        bxsMintSum += bxsAmtI256;

        // Mint the BXS to the AMO
        BXS.poolMint(destinationAmo, bxsAmount);

        // Sync
        syncBtcBalances();
    }

    function burnBxsFromAMO(uint256 bxsAmount) external validAMO(msg.sender) {
        int256 bxsAmtI256 = int256(bxsAmount);

        // Burn first
        BXS.poolBurnFrom(msg.sender, bxsAmount);

        // Then update the balances
        bxsMintBalances[msg.sender] -= bxsAmtI256;
        bxsMintSum -= bxsAmtI256;

        // Sync
        syncBtcBalances();
    }

    // ------------------------------------------------------------------
    // --------------------------- Collateral ---------------------------
    // ------------------------------------------------------------------

    function giveCollatToAMO(
        address destinationAmo,
        uint256 collatAmount
    ) external onlyByOwnGov validAMO(destinationAmo) {
        int256 collatAmountI256 = int256(collatAmount);

        // Ensure the amount being borrowed is below the cap allowed to borrow
        require((collatBorrowedSum + collatAmountI256) <= collatBorrowCap, "Borrow cap");
        collatBorrowedBalances[destinationAmo] += collatAmountI256;
        collatBorrowedSum += collatAmountI256;

        // Borrow the collateral
        pool.amoMinterBorrow(collatAmount);

        // Give the collateral from the minter to the AMO
        TransferHelper.safeTransfer(collateralAddress, destinationAmo, collatAmount);

        // Sync
        syncBtcBalances();
    }

    function receiveCollatFromAMO(uint256 collatAmount) external validAMO(msg.sender) {
        int256 collatAmountI256 = int256(collatAmount);

        // Give collateral from the AMO to the pool first
        TransferHelper.safeTransferFrom(collateralAddress, msg.sender, address(pool), collatAmount);

        // Then update the balances
        collatBorrowedBalances[msg.sender] -= collatAmountI256;
        collatBorrowedSum -= collatAmountI256;

        // Sync
        syncBtcBalances();
    }

    /* ========== RESTRICTED GOVERNANCE FUNCTIONS ========== */

    // Adds an AMO 
    function addAMO(address amoAddress, bool syncToo) public onlyByOwnGov {
        require(amoAddress != address(0), "Zero address detected");

        (uint256 braxValE18, uint256 collatValE18) = IAMO(amoAddress).btcBalances();
        require(braxValE18 >= 0 && collatValE18 >= 0, "Invalid AMO");

        require(amos[amoAddress] == false, "Address already exists");
        amos[amoAddress] = true; 
        amosArray.push(amoAddress);

        // Mint balances
        braxMintBalances[amoAddress] = 0;
        bxsMintBalances[amoAddress] = 0;
        collatBorrowedBalances[amoAddress] = 0;

        // Offsets
        correctionOffsetsAmos[amoAddress][0] = 0;
        correctionOffsetsAmos[amoAddress][1] = 0;

        if (syncToo) syncBtcBalances();

        emit AMOAdded(amoAddress);
    }

    // Removes an AMO
    function removeAMO(address amoAddress, bool syncToo) public onlyByOwnGov {
        require(amoAddress != address(0), "Zero address detected");
        require(amos[amoAddress] == true, "Address nonexistant");

        // Delete from the mapping
        delete amos[amoAddress];

        // 'Delete' from the array by setting the address to 0x0
        for (uint i = 0; i < amosArray.length; i++){ 
            if (amosArray[i] == amoAddress) {
                amosArray[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }

        if (syncToo) syncBtcBalances();

        emit AMORemoved(amoAddress);
    }

    function setTimelock(address newTimelock) external onlyByOwnGov {
        require(newTimelock != address(0), "Timelock address cannot be 0");
        timelockAddress = newTimelock;
    }

    function setCustodian(address _custodianAddress) external onlyByOwnGov {
        require(_custodianAddress != address(0), "Custodian address cannot be 0");        
        custodianAddress = _custodianAddress;
    }

    function setBraxMintCap(uint256 _braxMintCap) external onlyByOwnGov {
        braxMintCap = int256(_braxMintCap);
    }

    function setBxsMintCap(uint256 _bxsMintCap) external onlyByOwnGov {
        bxsMintCap = int256(_bxsMintCap);
    }

    function setCollatBorrowCap(uint256 _collatBorrowCap) external onlyByOwnGov {
        collatBorrowCap = int256(_collatBorrowCap);
    }

    function setMinimumCollateralRatio(uint256 _minCr) external onlyByOwnGov {
        minCr = _minCr;
    }

    function setAMOCorrectionOffsets(address amoAddress, int256 braxE18Correction, int256 collatE18Correction) external onlyByOwnGov {
        correctionOffsetsAmos[amoAddress][0] = braxE18Correction;
        correctionOffsetsAmos[amoAddress][1] = collatE18Correction;

        syncBtcBalances();
    }

    function setBraxPool(address _poolAddress) external onlyByOwnGov {
        pool = BraxPoolV3(_poolAddress);

        // Make sure the collaterals match, or balances could get corrupted
        require(pool.collateralAddrToIdx(collateralAddress) == colIdx, "colIdx mismatch");
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyByOwnGov {
        // TODO: Should this contract ever hold tokens?  Should they be protected to prevent 
        // governance withdrawal?
        // Can only be triggered by owner or governance
        TransferHelper.safeTransfer(tokenAddress, owner, tokenAmount);

        emit Recovered(tokenAddress, tokenAmount);
    }

    // Generic proxy
    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyByGov returns (bool, bytes memory) {
        // Dangerous proxy - only allow to be executed through timelock as owner could be compromised
        (bool success, bytes memory result) = _to.call{value:_value}(_data);
        return (success, result);
    }

    /* ========== EVENTS ========== */

    event AMOAdded(address amoAddress);
    event AMORemoved(address amoAddress);
    event Recovered(address token, uint256 amount);
} 
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
import "../Brax/Pools/IBraxPool.sol";
import "../ERC20/ERC20.sol";
import "../Staking/Owned.sol";
import '../Uniswap/TransferHelper.sol';
import '../Misc_AMOs/IAMO.sol';

contract BraxAMOMinter is Owned {
    // SafeMath automatically included in Solidity >= 8.0.0

    /* ========== STATE VARIABLES ========== */

    // Core
    // TODO: Add BRAX contract
    IBrax public BRAX = IBrax(0x0000000000000000000000000000000000000000);
    // TODO: Add BXS contract
    IBxs public BXS = IBxs(0x0000000000000000000000000000000000000000);
    ERC20 public collateral_token;
    // TODO: Add BraxPoolV3 contract
    BraxPoolV3 public pool = BraxPoolV3(0x0000000000000000000000000000000000000000);
    address public timelock_address;
    address public custodian_address;

    // Collateral related
    address public collateral_address;
    uint256 public col_idx;

    // AMO addresses
    address[] public amos_array;
    mapping(address => bool) public amos; // Mapping is also used for faster verification

    // Price constants
    uint256 private constant PRICE_PRECISION = 1e8;

    // Max amount of collateral the contract can borrow from the BraxPool
    // Set to 250 BTC to match FRAX 10m
    int256 public collat_borrow_cap = int256(250e8);

    // Max amount of FRAX and FXS this contract can mint
    // Set to 2500 BRAX to match FRAX 100m, BXS stays the same
    int256 public brax_mint_cap = int256(2500e18);
    int256 public bxs_mint_cap = int256(100000000e18);

    // Minimum collateral ratio needed for new BRAX minting
    uint256 public min_cr = 81000000;

    // Brax mint balances
    mapping(address => int256) public brax_mint_balances; // Amount of BRAX the contract minted, by AMO
    int256 public brax_mint_sum = 0; // Across all AMOs

    // Bxs mint balances
    mapping(address => int256) public bxs_mint_balances; // Amount of BXS the contract minted, by AMO
    int256 public bxs_mint_sum = 0; // Across all AMOs

    // Collateral borrowed balances
    mapping(address => int256) public collat_borrowed_balances; // Amount of collateral the contract borrowed, by AMO
    int256 public collat_borrowed_sum = 0; // Across all AMOs

    // BRAX balance related
    uint256 public braxBtcBalanceStored = 0;

    // Collateral balance related
    uint256 public missing_decimals;
    uint256 public collatBtcBalanceStored = 0;

    // AMO balance corrections
    mapping(address => int256[2]) public correction_offsets_amos;
    // [amo_address][0] = AMO's brax_val_e18
    // [amo_address][1] = AMO's collat_val_e18

    /* ========== CONSTRUCTOR ========== */
    
    constructor (
        address _owner_address,
        address _custodian_address,
        address _timelock_address,
        address _collateral_address,
        address _pool_address
    ) Owned(_owner_address) {
        custodian_address = _custodian_address;
        timelock_address = _timelock_address;

        // Pool related
        pool = BraxPoolV3(_pool_address);

        // Collateral related
        collateral_address = _collateral_address;
        col_idx = pool.collateralAddrToIdx(_collateral_address);
        collateral_token = ERC20(_collateral_address);
        missing_decimals = uint(18) - collateral_token.decimals();
    }

    /* ========== MODIFIERS ========== */

    modifier onlyByGov() {
        require(msg.sender == timelock_address, "Not timelock");
        _;
    }

    modifier onlyByOwnGov() {
        require(msg.sender == timelock_address || msg.sender == owner, "Not owner or timelock");
        _;
    }

    modifier validAMO(address amo_address) {
        require(amos[amo_address], "Invalid AMO");
        _;
    }

    /* ========== VIEWS ========== */

    function collatBtcBalance() external view returns (uint256) {
        (, uint256 collat_val_e18) = btcBalances();
        return collat_val_e18;
    }

    function btcBalances() public view returns (uint256 brax_val_e18, uint256 collat_val_e18) {
        brax_val_e18 = braxBtcBalanceStored;
        collat_val_e18 = collatBtcBalanceStored;
    }

    function allAMOAddresses() external view returns (address[] memory) {
        return amos_array;
    }

    function allAMOsLength() external view returns (uint256) {
        return amos_array.length;
    }

    function braxTrackedGlobal() external view returns (int256) {
        return int256(braxBtcBalanceStored) - brax_mint_sum - (collat_borrowed_sum * int256(10 ** missing_decimals));
    }

    function braxTrackedAMO(address amo_address) external view returns (int256) {
        (uint256 brax_val_e18, ) = IAMO(amo_address).btcBalances();
        int256 brax_val_e18_corrected = int256(brax_val_e18) + correction_offsets_amos[amo_address][0];
        return brax_val_e18_corrected - brax_mint_balances[amo_address] - ((collat_borrowed_balances[amo_address]) * int256(10 ** missing_decimals));
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    // Callable by anyone willing to pay the gas
    function syncBtcBalances() public {
        uint256 total_brax_value_d18 = 0;
        uint256 total_collateral_value_d18 = 0; 
        for (uint i = 0; i < amos_array.length; i++){ 
            // Exclude null addresses
            address amo_address = amos_array[i];
            if (amo_address != address(0)){
                (uint256 brax_val_e18, uint256 collat_val_e18) = IAMO(amo_address).btcBalances();
                total_brax_value_d18 += uint256(int256(brax_val_e18) + correction_offsets_amos[amo_address][0]);
                total_collateral_value_d18 += uint256(int256(collat_val_e18) + correction_offsets_amos[amo_address][1]);
            }
        }
        braxBtcBalanceStored = total_brax_value_d18;
        collatBtcBalanceStored = total_collateral_value_d18;
    }

    /* ========== OWNER / GOVERNANCE FUNCTIONS ONLY ========== */
    // Only owner or timelock can call, to limit risk 

    // ------------------------------------------------------------------
    // ------------------------------ BRAX ------------------------------
    // ------------------------------------------------------------------

    // This contract is essentially marked as a 'pool' so it can call OnlyPools functions like pool_mint and pool_burn_from
    // on the main BRAX contract
    function mintBraxForAMO(address destination_amo, uint256 brax_amount) external onlyByOwnGov validAMO(destination_amo) {
        int256 brax_amt_i256 = int256(brax_amount);

        // Make sure you aren't minting more than the mint cap
        require((brax_mint_sum + brax_amt_i256) <= brax_mint_cap, "Mint cap reached");
        brax_mint_balances[destination_amo] += brax_amt_i256;
        brax_mint_sum += brax_amt_i256;

        // Make sure the BRAX minting wouldn't push the CR down too much
        // This is also a sanity check for the int256 math
        uint256 current_collateral_E18 = BRAX.globalCollateralValue();
        uint256 cur_brax_supply = BRAX.totalSupply();
        uint256 new_brax_supply = cur_brax_supply + brax_amount;
        uint256 new_cr = (current_collateral_E18 * PRICE_PRECISION) / new_brax_supply;
        require(new_cr >= min_cr, "CR would be too low");

        // Mint the FRAX to the AMO
        BRAX.pool_mint(destination_amo, brax_amount);

        // Sync
        syncBtcBalances();
    }

    function burnBraxFromAMO(uint256 brax_amount) external validAMO(msg.sender) {
        int256 brax_amt_i256 = int256(brax_amount);

        // Burn first
        BRAX.pool_burn_from(msg.sender, brax_amount);

        // Then update the balances
        brax_mint_balances[msg.sender] -= brax_amt_i256;
        brax_mint_sum -= brax_amt_i256;

        // Sync
        syncBtcBalances();
    }

    // ------------------------------------------------------------------
    // ------------------------------- BXS ------------------------------
    // ------------------------------------------------------------------

    function mintBxsForAMO(address destination_amo, uint256 bxs_amount) external onlyByOwnGov validAMO(destination_amo) {
        int256 bxs_amt_i256 = int256(bxs_amount);

        // Make sure you aren't minting more than the mint cap
        require((bxs_mint_sum + bxs_amt_i256) <= bxs_mint_cap, "Mint cap reached");
        bxs_mint_balances[destination_amo] += bxs_amt_i256;
        bxs_mint_sum += bxs_amt_i256;

        // Mint the BXS to the AMO
        BXS.pool_mint(destination_amo, bxs_amount);

        // Sync
        syncBtcBalances();
    }

    function burnBxsFromAMO(uint256 bxs_amount) external validAMO(msg.sender) {
        int256 bxs_amt_i256 = int256(bxs_amount);

        // Burn first
        BXS.pool_burn_from(msg.sender, bxs_amount);

        // Then update the balances
        bxs_mint_balances[msg.sender] -= bxs_amt_i256;
        bxs_mint_sum -= bxs_amt_i256;

        // Sync
        syncBtcBalances();
    }

    // ------------------------------------------------------------------
    // --------------------------- Collateral ---------------------------
    // ------------------------------------------------------------------

    function giveCollatToAMO(
        address destination_amo,
        uint256 collat_amount
    ) external onlyByOwnGov validAMO(destination_amo) {
        int256 collat_amount_i256 = int256(collat_amount);

        // Ensure the amount being borrowed is below the cap allowed to borrow
        require((collat_borrowed_sum + collat_amount_i256) <= collat_borrow_cap, "Borrow cap");
        collat_borrowed_balances[destination_amo] += collat_amount_i256;
        collat_borrowed_sum += collat_amount_i256;

        // Borrow the collateral
        pool.amoMinterBorrow(collat_amount);

        // Give the collateral from the minter to the AMO
        TransferHelper.safeTransfer(collateral_address, destination_amo, collat_amount);

        // Sync
        syncBtcBalances();
    }

    function receiveCollatFromAMO(uint256 collat_amount) external validAMO(msg.sender) {
        int256 collat_amt_i256 = int256(collat_amount);

        // Give collateral from the AMO to the pool first
        TransferHelper.safeTransferFrom(collateral_address, msg.sender, address(pool), collat_amount);

        // Then update the balances
        collat_borrowed_balances[msg.sender] -= collat_amt_i256;
        collat_borrowed_sum -= collat_amt_i256;

        // Sync
        syncBtcBalances();
    }

    /* ========== RESTRICTED GOVERNANCE FUNCTIONS ========== */

    // Adds an AMO 
    function addAMO(address amo_address, bool sync_too) public onlyByOwnGov {
        require(amo_address != address(0), "Zero address detected");

        (uint256 brax_val_e18, uint256 collat_val_e18) = IAMO(amo_address).btcBalances();
        require(brax_val_e18 >= 0 && collat_val_e18 >= 0, "Invalid AMO");

        require(amos[amo_address] == false, "Address already exists");
        amos[amo_address] = true; 
        amos_array.push(amo_address);

        // Mint balances
        brax_mint_balances[amo_address] = 0;
        bxs_mint_balances[amo_address] = 0;
        collat_borrowed_balances[amo_address] = 0;

        // Offsets
        correction_offsets_amos[amo_address][0] = 0;
        correction_offsets_amos[amo_address][1] = 0;

        if (sync_too) syncBtcBalances();

        emit AMOAdded(amo_address);
    }

    // Removes an AMO
    function removeAMO(address amo_address, bool sync_too) public onlyByOwnGov {
        require(amo_address != address(0), "Zero address detected");
        require(amos[amo_address] == true, "Address nonexistant");
        
        // Delete from the mapping
        delete amos[amo_address];

        // 'Delete' from the array by setting the address to 0x0
        for (uint i = 0; i < amos_array.length; i++){ 
            if (amos_array[i] == amo_address) {
                amos_array[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }

        if (sync_too) syncBtcBalances();

        emit AMORemoved(amo_address);
    }

    function setTimelock(address new_timelock) external onlyByOwnGov {
        require(new_timelock != address(0), "Timelock address cannot be 0");
        timelock_address = new_timelock;
    }

    function setCustodian(address _custodian_address) external onlyByOwnGov {
        require(_custodian_address != address(0), "Custodian address cannot be 0");        
        custodian_address = _custodian_address;
    }

    function setBraxMintCap(uint256 _brax_mint_cap) external onlyByOwnGov {
        brax_mint_cap = int256(_brax_mint_cap);
    }

    function setBxsMintCap(uint256 _bxs_mint_cap) external onlyByOwnGov {
        bxs_mint_cap = int256(_bxs_mint_cap);
    }

    function setCollatBorrowCap(uint256 _collat_borrow_cap) external onlyByOwnGov {
        collat_borrow_cap = int256(_collat_borrow_cap);
    }

    function setMinimumCollateralRatio(uint256 _min_cr) external onlyByOwnGov {
        min_cr = _min_cr;
    }

    function setAMOCorrectionOffsets(address amo_address, int256 brax_e18_correction, int256 collat_e18_correction) external onlyByOwnGov {
        correction_offsets_amos[amo_address][0] = brax_e18_correction;
        correction_offsets_amos[amo_address][1] = collat_e18_correction;

        syncBtcBalances();
    }

    function setBraxPool(address _pool_address) external onlyByOwnGov {
        pool = BraxPoolV3(_pool_address);

        // Make sure the collaterals match, or balances could get corrupted
        require(pool.collateralAddrToIdx(collateral_address) == col_idx, "col_idx mismatch");
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

    event AMOAdded(address amo_address);
    event AMORemoved(address amo_address);
    event Recovered(address token, uint256 amount);
}
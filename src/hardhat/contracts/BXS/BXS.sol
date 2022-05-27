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
// ========================= BRAXShares (BXS) ===========================
// ======================================================================
// Brax Finance: https://github.com/BraxFinance

// Primary Author(s)
// Travis Moore: https://github.com/FortisFortuna
// Jason Huan: https://github.com/jasonhuan
// Sam Kazemian: https://github.com/samkazemian
// Andrew Mitchell: https://github.com/mitche50

// Reviewer(s) / Contributor(s)
// Sam Sun: https://github.com/samczsun

import "../Common/Context.sol";
import "../ERC20/ERC20Custom.sol";
import "../ERC20/IERC20.sol";
import "../Brax/Brax.sol";
import "../Staking/Owned.sol";
import "../Math/SafeMath.sol";
import "../Governance/AccessControl.sol";

contract BRAXShares is ERC20Custom, AccessControl, Owned {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    string public symbol;
    string public name;
    uint8 public constant decimals = 18;
    
    uint256 public constant genesisSupply = 100000000e18; // 100M is printed upon genesis
    uint256 public BXS_DAO_MIN; // Minimum BXS required to join DAO groups 

    address public ownerAddress;
    address public oracleAddress;
    address public timelockAddress; // Governance timelock address
    BRAXBtcSynth private BRAX;

    bool public trackingVotes = true; // Tracking votes (only change if need to disable votes)

    // A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    // A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    // The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /* ========== MODIFIERS ========== */

    modifier onlyPools() {
       require(BRAX.braxPools(msg.sender) == true, "Only brax pools can mint new BXS");
        _;
    } 
    
    modifier onlyByOwnGov() {
        require(msg.sender == owner || msg.sender == timelockAddress, "You are not an owner or the governance timelock");
        _;
    }

    modifier onlyByOwnerOrGovernance() {
        require(msg.sender == owner || msg.sender == timelockAddress, "Not the owner or the governance timelock");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (
        string memory _name,
        string memory _symbol, 
        address _oracleAddress,
        address _creatorAddress,
        address _timelockAddress
    ) public Owned(_creatorAddress){
        require((_oracleAddress != address(0)) && (_timelockAddress != address(0)), "Zero address detected"); 
        name = _name;
        symbol = _symbol;
        oracleAddress = _oracleAddress;
        timelockAddress = _timelockAddress;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _mint(_creatorAddress, genesisSupply);

        // Do a checkpoint for the owner
        _writeCheckpoint(_creatorAddress, 0, 0, uint96(genesisSupply));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Sets the oracle address for BXS
     * @param newOracle Address of the new BXS oracle
     */
    function setOracle(address newOracle) external onlyByOwnGov {
        require(newOracle != address(0), "Zero address detected");

        oracleAddress = newOracle;
    }

    /**
     * @notice Set a new timelock address
     * @param newTimelock Address of the new timelock
     */
    function setTimelock(address newTimelock) external onlyByOwnGov {
        require(newTimelock != address(0), "Timelock address cannot be 0");
        timelockAddress = newTimelock;
    }

    /**
     * @notice Set the address of BRAX
     * @param braxContractAddress Address of BRAX
     */
    function setBRAXAddress(address braxContractAddress) external onlyByOwnGov {
        require(braxContractAddress != address(0), "Zero address detected");

        BRAX = BRAXBtcSynth(braxContractAddress);

        emit BRAXAddressSet(braxContractAddress);
    }

    /**
     * @notice Set the minimum amount of BXS required to join DAO
     * @param minBXS amount of BXS required to join DAO
     */
    function setBXSMinDAO(uint256 minBXS) external onlyByOwnerOrGovernance {
        BXS_DAO_MIN = minBXS;
    }
    
    /**
     * @notice Mint new BXS
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) public onlyPools {
        _mint(to, amount);
    }
    
    /**
     * @notice Mint new BXS via pool
     * @param mAddress Address to mint to
     * @param mAmount Amount to mint
     */
    function poolMint(address mAddress, uint256 mAmount) external onlyPools {        
        if(trackingVotes){
            uint32 srcRepNum = numCheckpoints[address(this)];
            uint96 srcRepOld = srcRepNum > 0 ? checkpoints[address(this)][srcRepNum - 1].votes : 0;
            uint96 srcRepNew = add96(srcRepOld, uint96(mAmount), "poolMint new votes overflows");
            _writeCheckpoint(address(this), srcRepNum, srcRepOld, srcRepNew); // mint new votes
            trackVotes(address(this), mAddress, uint96(mAmount));
        }

        super._mint(mAddress, mAmount);
        emit BXSMinted(address(this), mAddress, mAmount);
    }

    /**
     * @notice Burn BXS via pool
     * @param bAddress Address to burn from
     * @param bAmount Amount to burn
     */
    function poolBurnFrom(address bAddress, uint256 bAmount) external onlyPools {
        if(trackingVotes){
            trackVotes(bAddress, address(this), uint96(bAmount));
            uint32 srcRepNum = numCheckpoints[address(this)];
            uint96 srcRepOld = srcRepNum > 0 ? checkpoints[address(this)][srcRepNum - 1].votes : 0;
            uint96 srcRepNew = sub96(srcRepOld, uint96(bAmount), "poolBurnFrom new votes underflows");
            _writeCheckpoint(address(this), srcRepNum, srcRepOld, srcRepNew); // burn votes
        }

        super._burnFrom(bAddress, bAmount);
        emit BXSBurned(bAddress, address(this), bAmount);
    }

    /// @notice Toggles tracking votes
    function toggleVotes() external onlyByOwnGov {
        trackingVotes = !trackingVotes;
    }

    /* ========== OVERRIDDEN PUBLIC FUNCTIONS ========== */

    /// @dev Overwritten to track votes
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if(trackingVotes){
            // Transfer votes
            trackVotes(_msgSender(), recipient, uint96(amount));
        }

        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /// @dev Overwritten to track votes
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if(trackingVotes){
            // Transfer votes
            trackVotes(sender, recipient, uint96(amount));
        }

        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));

        return true;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view returns (uint96) {
        require(blockNumber < block.number, "BXS::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @dev From compound's _moveDelegates
    /// @dev Keep track of votes. "Delegates" is a misnomer here
    function trackVotes(address srcRep, address dstRep, uint96 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = sub96(srcRepOld, amount, "BXS::_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = add96(dstRepOld, amount, "BXS::_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address voter, uint32 nCheckpoints, uint96 oldVotes, uint96 newVotes) internal {
      uint32 blockNumber = safe32(block.number, "BXS::_writeCheckpoint: block number exceeds 32 bits");

      if (nCheckpoints > 0 && checkpoints[voter][nCheckpoints - 1].fromBlock == blockNumber) {
          checkpoints[voter][nCheckpoints - 1].votes = newVotes;
      } else {
          checkpoints[voter][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          numCheckpoints[voter] = nCheckpoints + 1;
      }

      emit VoterVotesChanged(voter, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function safe96(uint n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /* ========== EVENTS ========== */
    
    /// @notice An event thats emitted when a voters account's vote balance changes
    event VoterVotesChanged(address indexed voter, uint previousBalance, uint newBalance);

    // Track FXS burned
    event BXSBurned(address indexed from, address indexed to, uint256 amount);

    // Track FXS minted
    event BXSMinted(address indexed from, address indexed to, uint256 amount);

    event BRAXAddressSet(address addr);
}

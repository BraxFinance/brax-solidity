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
// ======================= BraxStableBTC (BRAX) =========================
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
import "../ERC20/IERC20.sol";
import "../ERC20/ERC20Custom.sol";
import "../ERC20/ERC20.sol";
import "../Math/SafeMath.sol";
import "../Staking/Owned.sol";
import "../BXS/BXS.sol";
import "./Pools/BraxPoolV3.sol";
import "../Oracle/UniswapPairOracle.sol";
import "../Oracle/ChainlinkWBTCBTCPriceConsumer.sol";
import "../Governance/AccessControl.sol";

import "hardhat/console.sol";

contract BRAXBtcSynth is ERC20Custom, AccessControl, Owned {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    enum PriceChoice { BRAX, BXS }
    ChainlinkWBTCBTCPriceConsumer private wbtc_btc_pricer;
    uint8 private wbtc_btc_pricer_decimals;
    UniswapPairOracle private braxWBtcOracle;
    UniswapPairOracle private bxsWBtcOracle;
    string public symbol;
    string public name;
    uint8 public constant decimals = 18;
    address public creator_address;
    address public timelock_address; // Governance timelock address
    address public controller_address; // Controller contract to dynamically adjust system parameters automatically
    address public bxs_address;
    address public brax_wbtc_oracle_address;
    address public bxs_wbtc_oracle_address;
    address public wbtc_address;
    address public wbtc_btc_consumer_address;
    uint256 public constant genesis_supply = 50e18; // 50 BRAX. This is to help with establishing the Uniswap pools, as they need liquidity

    // The addresses in this array are added by the oracle and these contracts are able to mint brax
    address[] public brax_pools_array;

    // Mapping is also used for faster verification
    mapping(address => bool) public brax_pools; 

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e8;
    
    uint256 public global_collateral_ratio; // 8 decimals of precision, e.g. 92410242 = 0.92410242
    uint256 public redemption_fee; // 8 decimals of precision, divide by 100000000 in calculations for fee
    uint256 public minting_fee; // 8 decimals of precision, divide by 100000000 in calculations for fee
    uint256 public brax_step; // Amount to change the collateralization ratio by upon refreshCollateralRatio()
    uint256 public refresh_cooldown; // Seconds to wait before being able to run refreshCollateralRatio() again
    uint256 public price_target; // The price of BRAX at which the collateral ratio will respond to; this value is only used for the collateral ratio mechanism and not for minting and redeeming which are hardcoded at 1 BTC
    uint256 public price_band; // The bound above and below the price target at which the refreshCollateralRatio() will not change the collateral ratio
    uint256 public MAX_COLLATERAL_RATIO = 1e8;

    address public DEFAULT_ADMIN_ADDRESS;
    bytes32 public constant COLLATERAL_RATIO_PAUSER = keccak256("COLLATERAL_RATIO_PAUSER");
    bool public collateral_ratio_paused = false;

    // EIP2612 ERC20Permit implementation
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    mapping(address => uint) public nonces;
    bytes32 public DOMAIN_SEPARATOR;

    /* ========== MODIFIERS ========== */
    modifier onlyCollateralRatioPauser() {
        require(hasRole(COLLATERAL_RATIO_PAUSER, msg.sender), "!pauser");
        _;
    }
    modifier onlyPools() {
       require(brax_pools[msg.sender] == true, "Only brax pools can call this function");
        _;
    } 
    modifier onlyByOwnerGovernanceOrController() {
        require(msg.sender == owner || msg.sender == timelock_address || msg.sender == controller_address, "Not the owner, controller, or the governance timelock");
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor (
        string memory _name,
        string memory _symbol,
        address _creator_address,
        address _timelock_address
    ) public Owned(_creator_address){
        require(_timelock_address != address(0), "Zero address detected"); 
        name = _name;
        symbol = _symbol;
        creator_address = _creator_address;
        timelock_address = _timelock_address;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        DEFAULT_ADMIN_ADDRESS = _msgSender();
        _mint(creator_address, genesis_supply);
        grantRole(COLLATERAL_RATIO_PAUSER, creator_address);
        grantRole(COLLATERAL_RATIO_PAUSER, timelock_address);
        brax_step = 250000; // 8 decimals of precision, equal to 0.25%
        global_collateral_ratio = 1e8; // brax system starts off fully collateralized (8 decimals of precision)
        refresh_cooldown = 3600; // Refresh cooldown period is set to 1 hour (3600 seconds) at genesis
        price_target = 1e8; // Collateral ratio will adjust according to the 1 BTC price target at genesis (e8)
        price_band = 500000; // Collateral ratio will not adjust if between 0.995 BTC and 1.005 BTC at genesis (e8)

        uint chainId;
        assembly {
            chainId := chainid()
        }
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes('1'));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                typeHash,
                hashedName,
                hashedVersion,
                chainId,
                address(this)
            )
        );
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Retrieves oracle price for the provided PriceChoice enum
     * @param choice Token to return pricing information for
     * @return price X tokens required for 1 BTC
     */
    function oracle_price(PriceChoice choice) internal view returns (uint256) {
        uint256 price_vs_wbtc = 0;
        uint256 pricer_decimals = 0;

        if (choice == PriceChoice.BRAX) {
            price_vs_wbtc = uint256(braxWBtcOracle.consult(wbtc_address, PRICE_PRECISION)); // How much BRAX if you put in PRICE_PRECISION WBTC
            pricer_decimals = braxWBtcOracle.decimals();
        }
        else if (choice == PriceChoice.BXS) {
            price_vs_wbtc = uint256(bxsWBtcOracle.consult(wbtc_address, PRICE_PRECISION)); // How much BXS if you put in PRICE_PRECISION WBTC
            pricer_decimals = bxsWBtcOracle.decimals();
        }
        else revert("INVALID PRICE CHOICE. Needs to be either BRAX or BXS");

        return uint256(wbtc_btc_pricer.getLatestPrice()).mul(uint256(10) ** pricer_decimals).div(price_vs_wbtc);
    }

    /// @return price X BRAX = 1 BTC
    function brax_price() public view returns (uint256) {
        return oracle_price(PriceChoice.BRAX);
    }

    /// @return price X BXS = 1 BTC
    function bxs_price()  public view returns (uint256) {
        return oracle_price(PriceChoice.BXS);
    }

    /**
     * @notice Return all info regarding BRAX
     * @dev This is needed to avoid costly repeat calls to different getter functions
     * @dev It is cheaper gas-wise to just dump everything and only use some of the info
     * @return braxPrice Oracle price of BRAX
     * @return bxsPrice Oracle price of BXS
     * @return totalSupply of BRAX
     * @return global_collateral_ratio Current global collateral ratio of BRAX
     * @return globalCollateralValue Current free value in the BRAX system
     * @return minting_fee Fee to mint BRAX
     * @return redemption_fee Feed to redeem BRAX
     */
    function brax_info() public view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (
            oracle_price(PriceChoice.BRAX), // brax_price()
            oracle_price(PriceChoice.BXS), // bxs_price()
            totalSupply(), // totalSupply()
            global_collateral_ratio, // global_collateral_ratio()
            globalCollateralValue(), // globalCollateralValue
            minting_fee, // minting_fee()
            redemption_fee // redemption_fee()
        );
    }

    /**
     * @notice Iterate through all brax pools and calculate all value of collateral in all pools globally denominated in BTC
     * @return balance Balance of all pools denominated in BTC (e18)
     */
    function globalCollateralValue() public view returns (uint256) {
        uint256 total_collateral_value_d18 = 0; 

        for (uint i = 0; i < brax_pools_array.length; i++){ 
            // Exclude null addresses
            if (brax_pools_array[i] != address(0)){
                total_collateral_value_d18 = total_collateral_value_d18.add(BraxPoolV3(brax_pools_array[i]).collatBtcBalance());
            }
        }
        return total_collateral_value_d18;
    }

    /* ========== PUBLIC FUNCTIONS ========== */
    
    /**
     * @notice Update the collateral ratio based on the current price of BRAX
     * @dev last_call_time limits updates to once per hour to prevent multiple calls per expansion
     */
    uint256 public last_call_time; // Last time the refreshCollateralRatio function was called
    function refreshCollateralRatio() public {
        require(collateral_ratio_paused == false, "Collateral Ratio has been paused");
        require(block.timestamp - last_call_time >= refresh_cooldown, "Must wait for the refresh cooldown since last refresh");
        uint256 brax_price_cur = brax_price();

        // Step increments are 0.25% (upon genesis, changable by setBraxStep()) 
        if (brax_price_cur > price_target.add(price_band)) { //decrease collateral ratio
            if(global_collateral_ratio <= brax_step){ //if within a step of 0, go to 0
                global_collateral_ratio = 0;
            } else {
                global_collateral_ratio = global_collateral_ratio.sub(brax_step);
            }
        } else if (brax_price_cur < price_target.sub(price_band)) { //increase collateral ratio
            if(global_collateral_ratio.add(brax_step) >= MAX_COLLATERAL_RATIO){
                global_collateral_ratio = MAX_COLLATERAL_RATIO; // cap collateral ratio at 1.00000000
            } else {
                global_collateral_ratio = global_collateral_ratio.add(brax_step);
            }
        }

        last_call_time = block.timestamp; // Set the time of the last expansion

        emit CollateralRatioRefreshed(global_collateral_ratio);
    }

    /**
     * @notice Nonces for permit
     * @param owner Token owner's address (Authorizer)
     * @return next nonce
     */
    function permitNonces(address owner) external view returns (uint256) {
        return nonces[owner];
    }

    /**
     * @notice Verify a signed approval permit and execute if valid
     * @param owner     Token owner's address (Authorizer)
     * @param spender   Spender's address
     * @param value     Amount of allowance
     * @param deadline  The time at which this expires (unix time)
     * @param v         v of the signature
     * @param r         r of the signature
     * @param s         s of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "BRAX: permit is expired");

        bytes memory data = abi.encode(
            PERMIT_TYPEHASH,
            owner,
            spender,
            value,
            nonces[owner],
            deadline
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(data)
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'BRAX: INVALID_SIGNATURE');

        _approve(owner, spender, value);
        nonces[owner] += 1;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Potential improvement - create Burn Pool and send BRAX there which can be burnt by governance in batches
    // rather than opening up a burnFrom function which may be more dangerous.
    /**
     * @notice Burn BRAX as a step for releasing collateral
     * @param b_address address of user to burn from
     * @param b_amount amount of tokens to burn
    */
    function pool_burn_from(address b_address, uint256 b_amount) public onlyPools {
        super._burnFrom(b_address, b_amount);
        emit BRAXBurned(b_address, msg.sender, b_amount);
    }

    /**
     * @notice Mint BRAX via pools after depositing collateral
     * @param m_address address of user to mint to
     * @param m_amount amount of tokens to mint
    */
    function pool_mint(address m_address, uint256 m_amount) public onlyPools {
        super._mint(m_address, m_amount);
        emit BRAXMinted(msg.sender, m_address, m_amount);
    }

    /**
     * @notice Add a new pool to be used for collateral, such as wBTC and renBTC, must be ERC20 
     * @param pool_address address of pool to add
    */
    function addPool(address pool_address) public onlyByOwnerGovernanceOrController {
        require(pool_address != address(0), "Zero address detected");

        require(brax_pools[pool_address] == false, "Address already exists");
        brax_pools[pool_address] = true; 
        brax_pools_array.push(pool_address);

        emit PoolAdded(pool_address);
    }

    /**
     * @notice Remove a pool, leaving a 0x0 address in the index to retain the order of the other pools
     * @param pool_address address of pool to remove
    */
    function removePool(address pool_address) public onlyByOwnerGovernanceOrController {
        require(pool_address != address(0), "Zero address detected");
        require(brax_pools[pool_address] == true, "Address nonexistant");
        
        // Delete from the mapping
        delete brax_pools[pool_address];

        // 'Delete' from the array by setting the address to 0x0
        for (uint i = 0; i < brax_pools_array.length; i++){ 
            if (brax_pools_array[i] == pool_address) {
                brax_pools_array[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }

        emit PoolRemoved(pool_address);
    }

    /**
     * @notice Set fee for redemption of BRAX to collateral
     * @param red_fee fee in 8 decimal precision (e.g. 100000000 = 1% redemption fee)
    */
    function setRedemptionFee(uint256 red_fee) public onlyByOwnerGovernanceOrController {
        redemption_fee = red_fee;

        emit RedemptionFeeSet(red_fee);
    }

    /**
     * @notice Set fee for minting BRAX from collateral
     * @param min_fee fee in 8 decimal precision (e.g. 100000000 = 1% minting fee)
    */
    function setMintingFee(uint256 min_fee) public onlyByOwnerGovernanceOrController {
        minting_fee = min_fee;

        emit MintingFeeSet(min_fee);
    }  

    /**
     * @notice Set the step that the collateral rate can be changed by
     * @param _new_step step in 8 decimal precision (e.g. 250000 = 0.25%)
    */
    function setBraxStep(uint256 _new_step) public onlyByOwnerGovernanceOrController {
        brax_step = _new_step;

        emit BraxStepSet(_new_step);
    }  

    /**
     * @notice Set the price target BRAX is aiming to stay at
     * @param _new_price_target price for BRAX to target in 8 decimals precision (e.g. 10000000 = 1 BTC)
    */
    function setPriceTarget(uint256 _new_price_target) public onlyByOwnerGovernanceOrController {
        price_target = _new_price_target;

        emit PriceTargetSet(_new_price_target);
    }

    /**
     * @notice Set the rate at which the collateral rate can be updated
     * @param _new_cooldown cooldown length in seconds (e.g. 3600 = 1 hour)
    */
    function setRefreshCooldown(uint256 _new_cooldown) public onlyByOwnerGovernanceOrController {
    	refresh_cooldown = _new_cooldown;

        emit RefreshCooldownSet(_new_cooldown);
    }

    /**
     * @notice Set the address for BXS
     * @param _bxs_address new address for BXS
    */
    function setBXSAddress(address _bxs_address) public onlyByOwnerGovernanceOrController {
        require(_bxs_address != address(0), "Zero address detected");

        bxs_address = _bxs_address;

        emit BXSAddressSet(_bxs_address);
    }

    /**
     * @notice Set the wBTC / BTC Oracle
     * @param _wbtc_btc_consumer_address new address for the oracle
    */
    function setWBTCBTCOracle(address _wbtc_btc_consumer_address) public onlyByOwnerGovernanceOrController {
        require(_wbtc_btc_consumer_address != address(0), "Zero address detected");

        wbtc_btc_consumer_address = _wbtc_btc_consumer_address;
        wbtc_btc_pricer = ChainlinkWBTCBTCPriceConsumer(wbtc_btc_consumer_address);
        wbtc_btc_pricer_decimals = wbtc_btc_pricer.getDecimals();

        emit WBTCBTCOracleSet(_wbtc_btc_consumer_address);
    }

    /**
     * @notice Set the governance timelock address
     * @param new_timelock new address for the timelock
    */
    function setTimelock(address new_timelock) external onlyByOwnerGovernanceOrController {
        require(new_timelock != address(0), "Zero address detected");

        timelock_address = new_timelock;

        emit TimelockSet(new_timelock);
    }

    /**
     * @notice Set the controller address
     * @param _controller_address new address for the controller
    */
    function setController(address _controller_address) external onlyByOwnerGovernanceOrController {
        require(_controller_address != address(0), "Zero address detected");

        controller_address = _controller_address;

        emit ControllerSet(_controller_address);
    }

    /**
     * @notice Set the tolerance away from the target price in which the collateral rate cannot be updated
     * @param _price_band new tolerance with 8 decimals precision (e.g. 500000 will not adjust if between 0.995 BTC and 1.005 BTC)
    */
    function setPriceBand(uint256 _price_band) external onlyByOwnerGovernanceOrController {
        price_band = _price_band;

        emit PriceBandSet(_price_band);
    }

    /**
     * @notice Set the BRAX / wBTC Oracle
     * @param _brax_oracle_addr new address for the oracle
    */
    function setBRAXWBtcOracle(address _brax_oracle_addr, address _wbtc_address) public onlyByOwnerGovernanceOrController {
        require((_brax_oracle_addr != address(0)) && (_wbtc_address != address(0)), "Zero address detected");
        brax_wbtc_oracle_address = _brax_oracle_addr;
        braxWBtcOracle = UniswapPairOracle(_brax_oracle_addr); 
        wbtc_address = _wbtc_address;

        emit BRAXWBTCOracleSet(_brax_oracle_addr, _wbtc_address);
    }

    /**
     * @notice Set the BXS / wBTC Oracle
     * @param _bxs_oracle_addr new address for the oracle
    */
    function setBXSWBtcOracle(address _bxs_oracle_addr, address _wbtc_address) public onlyByOwnerGovernanceOrController {
        require((_bxs_oracle_addr != address(0)) && (_wbtc_address != address(0)), "Zero address detected");

        bxs_wbtc_oracle_address = _bxs_oracle_addr;
        bxsWBtcOracle = UniswapPairOracle(_bxs_oracle_addr);
        wbtc_address = _wbtc_address;

        emit BXSWBTCOracleSet(_bxs_oracle_addr, _wbtc_address);
    }

    /// @notice Toggle if the Collateral Ratio should be able to be updated
    function toggleCollateralRatio() public onlyCollateralRatioPauser {
        collateral_ratio_paused = !collateral_ratio_paused;

        emit CollateralRatioToggled(collateral_ratio_paused);
    }

    /* ========== EVENTS ========== */
    event BRAXBurned(address indexed from, address indexed to, uint256 amount);
    event BRAXMinted(address indexed from, address indexed to, uint256 amount);
    event CollateralRatioRefreshed(uint256 global_collateral_ratio);
    event PoolAdded(address pool_address);
    event PoolRemoved(address pool_address);
    event RedemptionFeeSet(uint256 red_fee);
    event MintingFeeSet(uint256 min_fee);
    event BraxStepSet(uint256 new_step);
    event PriceTargetSet(uint256 new_price_target);
    event RefreshCooldownSet(uint256 new_cooldown);
    event BXSAddressSet(address _bxs_address);
    event TimelockSet(address new_timelock);
    event ControllerSet(address controller_address);
    event PriceBandSet(uint256 price_band);
    event WBTCBTCOracleSet(address wbtc_oracle_addr);
    event BRAXWBTCOracleSet(address brax_oracle_addr, address wbtc_address);
    event BXSWBTCOracleSet(address bxs_oracle_addr, address wbtc_address);
    event CollateralRatioToggled(bool collateral_ratio_paused);
}

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

contract BRAXBtcSynth is ERC20Custom, AccessControl, Owned {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    enum PriceChoice { BRAX, BXS }
    ChainlinkWBTCBTCPriceConsumer private wbtcBtcPricer;
    uint8 private wbtcBtcPricerDecimals;
    UniswapPairOracle private braxWBtcOracle;
    UniswapPairOracle private bxsWBtcOracle;
    string public symbol;
    string public name;
    uint8 public constant decimals = 18;
    address public creatorAddress;
    address public timelockAddress; // Governance timelock address
    address public controllerAddress; // Controller contract to dynamically adjust system parameters automatically
    address public bxsAddress;
    address public braxWbtcOracleAddress;
    address public bxsWbtcOracleAddress;
    address public wbtcAddress;
    address public wbtcBtcConsumerAddress;
    uint256 public constant genesisSupply = 50e18; // 50 BRAX. This is to help with establishing the Uniswap pools, as they need liquidity

    // The addresses in this array are added by the oracle and these contracts are able to mint brax
    address[] public braxPoolsArray;

    // Mapping is also used for faster verification
    mapping(address => bool) public braxPools; 

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e8;
    
    uint256 public globalCollateralRatio; // 8 decimals of precision, e.g. 92410242 = 0.92410242
    uint256 public redemptionFee; // 8 decimals of precision, divide by 100000000 in calculations for fee
    uint256 public mintingFee; // 8 decimals of precision, divide by 100000000 in calculations for fee
    uint256 public braxStep; // Amount to change the collateralization ratio by upon refreshCollateralRatio()
    uint256 public refreshCooldown; // Seconds to wait before being able to run refreshCollateralRatio() again
    uint256 public priceTarget; // The price of BRAX at which the collateral ratio will respond to; this value is only used for the collateral ratio mechanism and not for minting and redeeming which are hardcoded at 1 BTC
    uint256 public priceBand; // The bound above and below the price target at which the refreshCollateralRatio() will not change the collateral ratio
    uint256 public MAX_COLLATERAL_RATIO = 1e8;

    address public DEFAULT_ADMIN_ADDRESS;
    bytes32 public constant COLLATERAL_RATIO_PAUSER = keccak256("COLLATERAL_RATIO_PAUSER");
    bool public collateralRatioPaused = false;

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
       require(braxPools[msg.sender] == true, "Only brax pools can call this function");
        _;
    } 
    modifier onlyByOwnerGovernanceOrController() {
        require(msg.sender == owner || msg.sender == timelockAddress || msg.sender == controllerAddress, "Not the owner, controller, or the governance timelock");
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor (
        string memory _name,
        string memory _symbol,
        address _creatorAddress,
        address _timelockAddress
    ) public Owned(_creatorAddress){
        require(_timelockAddress != address(0), "Zero address detected"); 
        name = _name;
        symbol = _symbol;
        creatorAddress = _creatorAddress;
        timelockAddress = _timelockAddress;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        DEFAULT_ADMIN_ADDRESS = _msgSender();
        _mint(creatorAddress, genesisSupply);
        grantRole(COLLATERAL_RATIO_PAUSER, creatorAddress);
        grantRole(COLLATERAL_RATIO_PAUSER, timelockAddress);
        braxStep = 250000; // 8 decimals of precision, equal to 0.25%
        globalCollateralRatio = 1e8; // brax system starts off fully collateralized (8 decimals of precision)
        refreshCooldown = 3600; // Refresh cooldown period is set to 1 hour (3600 seconds) at genesis
        priceTarget = 1e8; // Collateral ratio will adjust according to the 1 BTC price target at genesis (e8)
        priceBand = 500000; // Collateral ratio will not adjust if between 0.995 BTC and 1.005 BTC at genesis (e8)

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
    function oraclePrice(PriceChoice choice) internal view returns (uint256 price) {
        uint256 priceVsWbtc = 0;
        uint256 pricerDecimals = 0;

        if (choice == PriceChoice.BRAX) {
            priceVsWbtc = uint256(braxWBtcOracle.consult(wbtcAddress, PRICE_PRECISION)); // How much BRAX if you put in PRICE_PRECISION WBTC
            pricerDecimals = braxWBtcOracle.decimals();
        }
        else if (choice == PriceChoice.BXS) {
            priceVsWbtc = uint256(bxsWBtcOracle.consult(wbtcAddress, PRICE_PRECISION)); // How much BXS if you put in PRICE_PRECISION WBTC
            pricerDecimals = bxsWBtcOracle.decimals();
        }
        else revert("INVALID PRICE CHOICE. Needs to be either BRAX or BXS");

        return uint256(wbtcBtcPricer.getLatestPrice()).mul(uint256(10) ** pricerDecimals).div(priceVsWbtc);
    }

    /// @return price X BRAX = 1 BTC
    function braxPrice() public view returns (uint256 price) {
        return oraclePrice(PriceChoice.BRAX);
    }

    /// @return price X BXS = 1 BTC
    function bxsPrice()  public view returns (uint256 price) {
        return oraclePrice(PriceChoice.BXS);
    }

    /**
     * @notice Return all info regarding BRAX
     * @dev This is needed to avoid costly repeat calls to different getter functions
     * @dev It is cheaper gas-wise to just dump everything and only use some of the info
     * @return braxPrice     Oracle price of BRAX
     * @return bxsPrice      Oracle price of BXS
     * @return supply        Total supply of BRAX
     * @return gcr           Current global collateral ratio of BRAX
     * @return gcv           Current free value in the BRAX system
     * @return mintingFee    Fee to mint BRAX
     * @return redemptionFee Fee to redeem BRAX
     */
    function braxInfo() public view returns (uint256 braxPrice, uint256 bxsPrice, uint256 supply, uint256 gcr, uint256 gcv, uint256 mintingFee, uint256 redemptionFee) {
        return (
            oraclePrice(PriceChoice.BRAX), // braxPrice()
            oraclePrice(PriceChoice.BXS), // bxsPrice()
            totalSupply(), // totalSupply()
            globalCollateralRatio, // globalCollateralRatio()
            globalCollateralValue(), // globalCollateralValue
            mintingFee, // mintingFee()
            redemptionFee // redemptionFee()
        );
    }

    /**
     * @notice Iterate through all brax pools and calculate all value of collateral in all pools globally denominated in BTC
     * @return balance Balance of all pools denominated in BTC (e18)
     */
    function globalCollateralValue() public view returns (uint256 balance) {
        uint256 totalCollateralValueD18 = 0; 

        for (uint i = 0; i < braxPoolsArray.length; i++){ 
            // Exclude null addresses
            if (braxPoolsArray[i] != address(0)){
                totalCollateralValueD18 = totalCollateralValueD18.add(BraxPoolV3(braxPoolsArray[i]).collatBtcBalance());
            }
        }
        return totalCollateralValueD18;
    }

    /* ========== PUBLIC FUNCTIONS ========== */
    
    /// @notice Last time the refreshCollateralRatio function was called
    uint256 public lastCallTime; 

    /**
     * @notice Update the collateral ratio based on the current price of BRAX
     * @dev lastCallTime limits updates to once per hour to prevent multiple calls per expansion
     */
    function refreshCollateralRatio() public {
        require(collateralRatioPaused == false, "Collateral Ratio has been paused");
        require(block.timestamp - lastCallTime >= refreshCooldown, "Must wait for the refresh cooldown since last refresh");
        uint256 braxPriceCur = braxPrice();

        // Step increments are 0.25% (upon genesis, changable by setBraxStep()) 
        if (braxPriceCur > priceTarget.add(priceBand)) { //decrease collateral ratio
            if(globalCollateralRatio <= braxStep){ //if within a step of 0, go to 0
                globalCollateralRatio = 0;
            } else {
                globalCollateralRatio = globalCollateralRatio.sub(braxStep);
            }
        } else if (braxPriceCur < priceTarget.sub(priceBand)) { //increase collateral ratio
            if(globalCollateralRatio.add(braxStep) >= MAX_COLLATERAL_RATIO){
                globalCollateralRatio = MAX_COLLATERAL_RATIO; // cap collateral ratio at 1.00000000
            } else {
                globalCollateralRatio = globalCollateralRatio.add(braxStep);
            }
        }

        lastCallTime = block.timestamp; // Set the time of the last expansion

        emit CollateralRatioRefreshed(globalCollateralRatio);
    }

    /**
     * @notice Nonces for permit
     * @param owner Token owner's address (Authorizer)
     * @return nonce next nonce
     */
    function permitNonces(address owner) external view returns (uint256 nonce) {
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
     * @param bAddress address of user to burn from
     * @param bAmount amount of tokens to burn
    */
    function poolBurnFrom(address bAddress, uint256 bAmount) public onlyPools {
        super._burnFrom(bAddress, bAmount);
        emit BRAXBurned(bAddress, msg.sender, bAmount);
    }

    /**
     * @notice Mint BRAX via pools after depositing collateral
     * @param mAddress address of user to mint to
     * @param mAmount amount of tokens to mint
    */
    function poolMint(address mAddress, uint256 mAmount) public onlyPools {
        super._mint(mAddress, mAmount);
        emit BRAXMinted(msg.sender, mAddress, mAmount);
    }

    /**
     * @notice Add a new pool to be used for collateral, such as wBTC and renBTC, must be ERC20 
     * @param poolAddress address of pool to add
    */
    function addPool(address poolAddress) public onlyByOwnerGovernanceOrController {
        require(poolAddress != address(0), "Zero address detected");

        require(braxPools[poolAddress] == false, "Address already exists");
        braxPools[poolAddress] = true; 
        braxPoolsArray.push(poolAddress);

        emit PoolAdded(poolAddress);
    }

    /**
     * @notice Remove a pool, leaving a 0x0 address in the index to retain the order of the other pools
     * @param poolAddress address of pool to remove
    */
    function removePool(address poolAddress) public onlyByOwnerGovernanceOrController {
        require(poolAddress != address(0), "Zero address detected");
        require(braxPools[poolAddress] == true, "Address nonexistant");
        
        // Delete from the mapping
        delete braxPools[poolAddress];

        // 'Delete' from the array by setting the address to 0x0
        for (uint i = 0; i < braxPoolsArray.length; i++){ 
            if (braxPoolsArray[i] == poolAddress) {
                braxPoolsArray[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }

        emit PoolRemoved(poolAddress);
    }

    /**
     * @notice Set fee for redemption of BRAX to collateral
     * @param redFee fee in 8 decimal precision (e.g. 100000000 = 1% redemption fee)
    */
    function setRedemptionFee(uint256 redFee) public onlyByOwnerGovernanceOrController {
        redemptionFee = redFee;

        emit RedemptionFeeSet(redFee);
    }

    /**
     * @notice Set fee for minting BRAX from collateral
     * @param minFee fee in 8 decimal precision (e.g. 100000000 = 1% minting fee)
    */
    function setMintingFee(uint256 minFee) public onlyByOwnerGovernanceOrController {
        mintingFee = minFee;

        emit MintingFeeSet(minFee);
    }  

    /**
     * @notice Set the step that the collateral rate can be changed by
     * @param _newStep step in 8 decimal precision (e.g. 250000 = 0.25%)
    */
    function setBraxStep(uint256 _newStep) public onlyByOwnerGovernanceOrController {
        braxStep = _newStep;

        emit BraxStepSet(_newStep);
    }  

    /**
     * @notice Set the price target BRAX is aiming to stay at
     * @param _newPriceTarget price for BRAX to target in 8 decimals precision (e.g. 10000000 = 1 BTC)
    */
    function setPriceTarget(uint256 _newPriceTarget) public onlyByOwnerGovernanceOrController {
        priceTarget = _newPriceTarget;

        emit PriceTargetSet(_newPriceTarget);
    }

    /**
     * @notice Set the rate at which the collateral rate can be updated
     * @param _newCooldown cooldown length in seconds (e.g. 3600 = 1 hour)
    */
    function setRefreshCooldown(uint256 _newCooldown) public onlyByOwnerGovernanceOrController {
    	refreshCooldown = _newCooldown;

        emit RefreshCooldownSet(_newCooldown);
    }

    /**
     * @notice Set the address for BXS
     * @param _bxsAddress new address for BXS
    */
    function setBXSAddress(address _bxsAddress) public onlyByOwnerGovernanceOrController {
        require(_bxsAddress != address(0), "Zero address detected");

        bxsAddress = _bxsAddress;

        emit BXSAddressSet(_bxsAddress);
    }

    /**
     * @notice Set the wBTC / BTC Oracle
     * @param _wbtcBtcConsumerAddress new address for the oracle
    */
    function setWBTCBTCOracle(address _wbtcBtcConsumerAddress) public onlyByOwnerGovernanceOrController {
        require(_wbtcBtcConsumerAddress != address(0), "Zero address detected");

        wbtcBtcConsumerAddress = _wbtcBtcConsumerAddress;
        wbtcBtcPricer = ChainlinkWBTCBTCPriceConsumer(wbtcBtcConsumerAddress);
        wbtcBtcPricerDecimals = wbtcBtcPricer.getDecimals();

        emit WBTCBTCOracleSet(_wbtcBtcConsumerAddress);
    }

    /**
     * @notice Set the governance timelock address
     * @param newTimelock new address for the timelock
    */
    function setTimelock(address newTimelock) external onlyByOwnerGovernanceOrController {
        require(newTimelock != address(0), "Zero address detected");

        timelockAddress = newTimelock;

        emit TimelockSet(newTimelock);
    }

    /**
     * @notice Set the controller address
     * @param _controllerAddress new address for the controller
    */
    function setController(address _controllerAddress) external onlyByOwnerGovernanceOrController {
        require(_controllerAddress != address(0), "Zero address detected");

        controllerAddress = _controllerAddress;

        emit ControllerSet(_controllerAddress);
    }

    /**
     * @notice Set the tolerance away from the target price in which the collateral rate cannot be updated
     * @param _priceBand new tolerance with 8 decimals precision (e.g. 500000 will not adjust if between 0.995 BTC and 1.005 BTC)
    */
    function setPriceBand(uint256 _priceBand) external onlyByOwnerGovernanceOrController {
        priceBand = _priceBand;

        emit PriceBandSet(_priceBand);
    }

    /**
     * @notice Set the BRAX / wBTC Oracle
     * @param _braxOracleAddr new address for the oracle
     * @param _wbtcAddress wBTC address for chain
    */
    function setBRAXWBtcOracle(address _braxOracleAddr, address _wbtcAddress) public onlyByOwnerGovernanceOrController {
        require((_braxOracleAddr != address(0)) && (_wbtcAddress != address(0)), "Zero address detected");
        braxWbtcOracleAddress = _braxOracleAddr;
        braxWBtcOracle = UniswapPairOracle(_braxOracleAddr); 
        wbtcAddress = _wbtcAddress;

        emit BRAXWBTCOracleSet(_braxOracleAddr, _wbtcAddress);
    }

    /**
     * @notice Set the BXS / wBTC Oracle
     * @param _bxsOracleAddr new address for the oracle
     * @param _wbtcAddress wBTC address for chain
    */
    function setBXSWBtcOracle(address _bxsOracleAddr, address _wbtcAddress) public onlyByOwnerGovernanceOrController {
        require((_bxsOracleAddr != address(0)) && (_wbtcAddress != address(0)), "Zero address detected");

        bxsWbtcOracleAddress = _bxsOracleAddr;
        bxsWBtcOracle = UniswapPairOracle(_bxsOracleAddr);
        wbtcAddress = _wbtcAddress;

        emit BXSWBTCOracleSet(_bxsOracleAddr, _wbtcAddress);
    }

    /// @notice Toggle if the Collateral Ratio should be able to be updated
    function toggleCollateralRatio() public onlyCollateralRatioPauser {
        collateralRatioPaused = !collateralRatioPaused;

        emit CollateralRatioToggled(collateralRatioPaused);
    }

    /* ========== EVENTS ========== */
    event BRAXBurned(address indexed from, address indexed to, uint256 amount);
    event BRAXMinted(address indexed from, address indexed to, uint256 amount);
    event CollateralRatioRefreshed(uint256 globalCollateralRatio);
    event PoolAdded(address poolAddress);
    event PoolRemoved(address poolAddress);
    event RedemptionFeeSet(uint256 redFee);
    event MintingFeeSet(uint256 minFee);
    event BraxStepSet(uint256 newStep);
    event PriceTargetSet(uint256 newPriceTarget);
    event RefreshCooldownSet(uint256 newCooldown);
    event BXSAddressSet(address _bxsAddress);
    event TimelockSet(address newTimelock);
    event ControllerSet(address controllerAddress);
    event PriceBandSet(uint256 priceBand);
    event WBTCBTCOracleSet(address wbtcOracleAddr);
    event BRAXWBTCOracleSet(address braxOracleAddr, address wbtcAddress);
    event BXSWBTCOracleSet(address bxsOracleAddr, address wbtcAddress);
    event CollateralRatioToggled(bool collateralRatioPaused);
}

// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.13;

import {Zax} from "./Zax.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title ZaxEngine
 * @author Ebenezer Jojo Mensah
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algoritmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our Zax system should always be "overcollateralized". At no point, should the value of all collateral <= the $ backed value of all the Zax.
 *
 * @notice This contract is the core of the Zax System. It handles all the logic for minting and redeeming Zax, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */

contract ZaxEngine is ReentrancyGuard {
    /////////////////
    ///Errors //////
    /////////////////
    error ZaxEngine__CollateralCanNotBeZero();
    error ZaxEngine__TokenAddressesAndPriceFeedAdressesMustBeSameLength();
    error ZaxEngine__NotAllowedToken();
    error ZaxEngine__TransferFailed();
    error ZaxEngine__BreaksHealthFactor(uint256 healthFactor);
    error ZaxEngine__MintFailed();
    error ZaxEngine__HealthFactorOk();
    error ZaxEngine_HealthFactorNotImproved();

    ///////////////////
    //State Variables//
    //////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollaterized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means 10% bonus

    mapping(address token => address priceFeed) private s_tokenToPriceFeed;

    // Map the user to the amount of a particular collateral deposited
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    // Map the user to amount of Zax minted
    mapping(address user => uint256 amountZaxMinted) private s_ZaxMinted;

    Zax private immutable i_zax;
    address[] private s_collateralTokens;

    /////////////////////
    //// Events /////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ////////////////
    ///Modifiers///
    /////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert ZaxEngine__CollateralCanNotBeZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_tokenToPriceFeed[token] == address(0)) {
            revert ZaxEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////
    ///Functions///
    /////////////////

    constructor(address[] memory tokenAdresses, address[] memory priceFeedAdresses, address zaxAddress) {
        // USD Price Feeds
        if (tokenAdresses.length != priceFeedAdresses.length) {
            revert ZaxEngine__TokenAddressesAndPriceFeedAdressesMustBeSameLength();
        }
        // Map token Adressess to their priceFeed Addresss
        for (uint256 i = 0; i < tokenAdresses.length; i++) {
            s_tokenToPriceFeed[tokenAdresses[i]] = priceFeedAdresses[i];
            s_collateralTokens.push(tokenAdresses[i]);
        }
        // assign the Zax addresss. Since i_zax is of type Zax and zaxAddress is of type address, hence Zax(zaxAddress)
        i_zax = Zax(zaxAddress);
    }

    ///////////////////
    /// External Functions///
    /////////////////

    /*
     *@notice follows CEI (Checks Effects Interactions)
     * @param tokenCollateralAdress: The address of the token to deposit as collateral
     * @param amountCollateral: The amount of collateral to deposit 
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        // Token Transfer
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert ZaxEngine__TransferFailed();
        }

        // Update State
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        // Event Emission
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param tokenCollateralAddress : the address of the token to deposit as collateral
     * @param amountCollateral : the amont of collateral to deposit
     * @param amountZaxToMint "the  amount of zax(stablecoin) to mint"
     * @notice this function will deposit your collateral and mint zax in one transaction
     */
    function depositCollateralAndMintZax(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountZaxToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintZax(amountZaxToMint);
    }

    // in order to reddem collateral:
    // 1. health factor must be over 1 After Collateral pulled
    // 2.
    function redeemCollateral(address tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, _amountCollateral, msg.sender, msg.sender);
        // check if health factor is broken
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param _tokenCollateralAddress The collateral address to redeem
     * @param _amountCollateral       The amount of collateral
     * @param _amountZaxToBurn  The amount of zax to burn
     * @notice This function burns zax and redeems underlying collateral in one transaction
     */
    function redeemCollateralForZax(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountZaxToBurn
    ) external moreThanZero(_amountCollateral) nonReentrant {
        burnZax(_amountZaxToBurn);
        // redeemCollateral already checks health Factor
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
    }

    /*
     *@notice follows CEI (Checks Effects Interactions)
     * @param amountZaxToMint: The amount of the Zax the user wants to mint   
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintZax(uint256 amountZaxToMint) public moreThanZero(amountZaxToMint) nonReentrant {
        s_ZaxMinted[msg.sender] += amountZaxToMint;

        //if they minted too much ($150 Zax => $100 BTC)
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_zax.mint(msg.sender, amountZaxToMint);
        if (!minted) {
            revert ZaxEngine__MintFailed();
        }
    }

    function burnZax(uint256 _amount) public moreThanZero(_amount) {
        _burnZax(_amount, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender); // This line may not hit
    }

    /**
     *
     * @param _tokencollateralAddress The erc20 collateral address to liquidate from user
     * @param _user The user who has broken the health factor i.e Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param _debtToCover The amount of Zax to burn to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquiddation bomus for taking the users funds
     * @notice This function assumes the protocol will be roughly 200% overcollateralized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentive the liquidators
     * For Example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address _tokencollateralAddress, address _user, uint256 _debtToCover)
        external
        moreThanZero(_debtToCover)
        nonReentrant
    {
        // check health factor of user
        uint256 startingUserHealthFactor = _healthFactor(_user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert ZaxEngine__HealthFactorOk();
        }

        // we want to burn their zax(debt) and take their collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(_tokencollateralAddress, _debtToCover);

        // Also give them a 10% bonus
        // So we are giving the liquidator $110 of Weth for 100 Zax
        // A feature will be implemented to liquidate in the event the protocol is insolvent
        // And sweep  extra amounts into the treasury
        // For 0.05 ETH * 0.1 = 0.005 ETH, Total = 0.05 ETH + 0.005 ETH = 0.055 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(_tokencollateralAddress, totalCollateralToRedeem, _user, msg.sender);

        // The Zax is Burned
        _burnZax(_debtToCover, _user, msg.sender);

        // Check if health factor has improved for user
        uint256 endingUserHealthFactor = _healthFactor(_user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert ZaxEngine_HealthFactorNotImproved();
        }

        // Check if the health factor has improved for msg.msg.sender
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ///////////////////
    ///Private & Internal View Functions ///
    /////////////////

    /**
     * @dev Low-level internal function, do not call unless the function calling it is checking for health factors being broken
     */
    function _burnZax(uint256 _amountZaxToBurn, address onBehalfOf, address zaxFrom) private {
        s_ZaxMinted[onBehalfOf] -= _amountZaxToBurn;
        bool success = i_zax.transferFrom(zaxFrom, address(this), _amountZaxToBurn);

        // This conditional is hypothetical unreacheable
        if (!success) {
            revert ZaxEngine__TransferFailed();
        }
        i_zax.burn(_amountZaxToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        // check if health factor is broken
        // _revertIfHealthFactorIsBroken(msg.sender);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);

        if (!success) {
            revert ZaxEngine__TransferFailed();
        }

        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalZaxMinted, uint256 collateralValueInUsd)
    {
        totalZaxMinted = s_ZaxMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     *
     * Returns how close to liquidattion a user is
     * If a user goes health factor goes below1, then they get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // get total Zax minted
        // get total collateral value
        (uint256 totalZaxMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        return _calculateHealthFactor(totalZaxMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check Health factor(do they have enough collateral?)
        uint256 userHealthFactor = _healthFactor(user);

        // 2. Revert if they don't
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert ZaxEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalZaxMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalZaxMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * 1e18) / totalZaxMinted;
    }

    ///////////////////
    ///Public and External View/Pure Functions///
    /////////////////

    function getTokenAmountFromUsd(address _token, uint256 _usdAmountInWei) public view returns (uint256) {
        // get price of token(Eg: ETH)
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (_usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to
        // the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to the price to get usd Value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        // User the AggregatorV3Interface to get the priceFeed in Usd of a Particular token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // If the price of eth is $1000, the value returned by AggregatorV3Interface will be 1000 * 1e8
        // Hence multiply ADDITIONAL_FEED_PRECISION = 1e10 to get 1e18 to have equal *unit
        // We then divide by PRECISION = 1e18  to get $1000 back
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION);
    }

    function getAccountInformation(address _user)
        external
        view
        returns (uint256 totalZaxMinted, uint256 collateralValueInUsd)
    {
        (totalZaxMinted, collateralValueInUsd) = _getAccountInformation(_user);
    }

    function getUserCollateral(address user, address tokenCollateralAddress) public view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateralAddress];
    }

    function getUserZaxMinted(address user) public view returns (uint256) {
        return s_ZaxMinted[user];
    }

    function getZaxContractAddress() external view returns (address) {
        return address(i_zax);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralTokensPriceFeed(address _token) external view returns (address) {
        return s_tokenToPriceFeed[_token];
    }
}

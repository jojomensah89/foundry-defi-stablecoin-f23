// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Zax} from "../../src/Zax.sol";
import {ZaxEngine} from "../../src/ZaxEngine.sol";
import {DeployZax} from "../../script/DeployZax.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";


contract ZaxEngineTest is Test {
    DeployZax deployer;
    ZaxEngine zaxEngine;
    Zax zax;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFee;
    address wbtc;

    address public USER = makeAddr("user");
    
    uint256 public  AMOUNT_COLLATERAL = 10 ether;
    uint256 public  AMOUNT_ZAX = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
     uint256 public constant STARTING_USER_BALANCE = 10 ether;

    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means 10% bonus
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    function setUp() public {
        deployer = new DeployZax();
        (zax, zaxEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFee, weth, wbtc,) = helperConfig.activeNetworkConfig();

           if (block.chainid == 31337) {
            vm.deal(USER, STARTING_USER_BALANCE);
        }

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
         ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    ///// Constructor Tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFee);

        vm.expectRevert(ZaxEngine.ZaxEngine__TokenAddressesAndPriceFeedAdressesMustBeSameLength.selector);
        new ZaxEngine(tokenAddresses,priceFeedAddresses,address(zax));
    }

    //// Price Tests

    function testGetUsdValue() public {
        // test Eth Price in Usd
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 30000e18; // 15e18 * 2000/ETH (price set in helperConfig) = 30,000e18
        uint256 actualUsd = zaxEngine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);

        // test Btc price in Usd
        uint256 btcAmount = 10e18;
        uint256 expectedUsdValue = 10000e18; //  10e18 * 1000/ETH (price set in helperConfig) = 10,000e18
        uint256 actualUsdValue = zaxEngine.getUsdValue(wbtc, btcAmount);
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;

        // For $2000 per Eth , $100 = 0.05 ether
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = zaxEngine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    //// deposit Collateral Tests
    

   
    function testRevertsWithZeroCollateral() public {
        vm.prank(USER);
        // vm.deal(USER,AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(zaxEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(ZaxEngine.ZaxEngine__CollateralCanNotBeZero.selector);
        zaxEngine.depositCollateral(weth, 0);
    }

    function testRevertsWithUnapprovedCollateral() public {
        // create a random token and attempt to use as collateral
        ERC20Mock randomToken = new ERC20Mock("RANDOM TOKEN", "RAN",USER,AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(ZaxEngine.ZaxEngine__NotAllowedToken.selector);
        zaxEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralWihtoutMintingZax() public depositedCollateral {
        uint256 userZaxBalance = zax.balanceOf(USER);
        assertEq(userZaxBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalZaxMinted, uint256 collateralValueInUsd) = zaxEngine.getAccountInformation(USER);

        uint256 expectedTotalZaxMinted = 0;
        uint256 expectedDepositAmount = zaxEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalZaxMinted, expectedTotalZaxMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    ////// deposit Collateral and Mint Zax
    

    function testDepositCollateralAndMintZax() public depositedCollateralAndmintZax {
        uint256 userZaxBalance = zax.balanceOf(USER);
        assertEq(userZaxBalance, AMOUNT_ZAX);
    }

    // // test Mint Zax
    function testRevertsIfMintAmountBreaksHealthFactor() public {
        // 0xe580cc6100000000000000000000000000000000000000000000000006f05b59d3b20000
        // 0xe580cc6100000000000000000000000000000000000000000000003635c9adc5dea00000
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        AMOUNT_ZAX = (AMOUNT_COLLATERAL * (uint256(price) * zaxEngine.getAdditionalFeedPrecision())) / zaxEngine.getPrecision();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(zaxEngine), AMOUNT_COLLATERAL);
        zaxEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor =
            zaxEngine.calculateHealthFactor(zaxEngine.getUsdValue(weth, AMOUNT_COLLATERAL), AMOUNT_ZAX);
        vm.expectRevert(abi.encodeWithSelector(ZaxEngine.ZaxEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        zaxEngine.mintZax(AMOUNT_ZAX);
        vm.stopPrank();
    }
    // function testCanNotMintZaxWithoutCollateralDeposit() public {
    //     // vm.expectRevert(ZaxEngine.ZaxEngine__CollateralCanNotBeZero.selector);
    //     vm.expectRevert();
    //        vm.startPrank(USER);
    //     // vm.deal(USER,AMOUNT_COLLATERAL);
    //     ERC20Mock(weth).approve(address(zaxEngine), AMOUNT_COLLATERAL);
    //     zaxEngine.depositCollateralAndMintZax(weth, 0,AMOUNT_ZAX);

    //     // zaxEngine.mintZax(AMOUNT_ZAX);
    //     vm.stopPrank();

    //     uint256 endingUserZaxBalance = zax.balanceOf(USER);
    //     assertEq(endingUserZaxBalance,AMOUNT_ZAX);
    // }

    function testCanMintZax() public depositedCollateral {
        vm.startPrank(USER);
        zaxEngine.mintZax(AMOUNT_ZAX);
        vm.stopPrank();

        uint256 endingUserZaxBalance = zax.balanceOf(USER);
        assertEq(AMOUNT_ZAX, endingUserZaxBalance);
    }

    function testCanNotMintZeroZax() public {
        vm.expectRevert();
        vm.startPrank(USER);
        zaxEngine.mintZax(0);
        vm.stopPrank();
    }

    /// test burn zax
    function testCanNotBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        zax.burn(1);
    }

    function testCanNotBurnZeroZax() public {
        vm.expectRevert();
        vm.startPrank(USER);
        zaxEngine.burnZax(0);
        vm.stopPrank();
    }

    function testBurnZax() public depositedCollateralAndmintZax {
        vm.startPrank(USER);
        zax.approve(address(zaxEngine), AMOUNT_ZAX);
        zaxEngine.burnZax(AMOUNT_ZAX);
        vm.stopPrank();
        uint256 endingUserZaxBalance = zax.balanceOf(USER);
        assertEq(endingUserZaxBalance, 0);
    }

    /// Getter Functions

    function testZaxContractAddress() public {
        assertEq(address(zax), address(zaxEngine.getZaxContractAddress()));
    }

    function testLiquidationThreshold() public {
        assertEq(zaxEngine.getLiquidationThreshold(), LIQUIDATION_THRESHOLD);
    }

    function testPrecision() public {
        assertEq(PRECISION, zaxEngine.getPrecision());
    }

    function testFeedAdditionalPrecision() public {
        assertEq(ADDITIONAL_FEED_PRECISION, zaxEngine.getAdditionalFeedPrecision());
    }

    function testMinHealthFactor() public {
        assertEq(MIN_HEALTH_FACTOR, zaxEngine.getMinHealthFactor());
    }

    function testLiquidationPrecision() public {
        assertEq(LIQUIDATION_PRECISION, zaxEngine.getLiquidationPrecision());
    }

    function testGetAccountCollateralValueInUsd() public depositedCollateral {
        uint256 userCollateralValueInUsd = zaxEngine.getUsdValue(weth, AMOUNT_COLLATERAL);

        assertEq(userCollateralValueInUsd, zaxEngine.getAccountCollateralValueInUsd(USER));
    }

    function testGetUserZaxMinted() public depositedCollateral {
        vm.startPrank(USER);
        zaxEngine.mintZax(AMOUNT_ZAX);
        vm.stopPrank();

        uint256 endingUserZaxBalance = zax.balanceOf(USER);
        assertEq(zaxEngine.getUserZaxMinted(USER), endingUserZaxBalance);
    }
    // function testCalculateHealthFactor () public {
    //     vm.startPrank(USER);
    //     zaxEngine.mintZax(AMOUNT_ZAX);
    //     vm.stopPrank();
    //             uint256 endingUserZaxBalance = zaxEngine.getUserZaxMinted(USER);

    //     zaxEngine.calculateHealthFactor();

    // }

    function testCollateralTokens() public {
        address[] memory collateralTokens = zaxEngine.getCollateralTokens();
        assertEq(weth, collateralTokens[0]);
        assertEq(wbtc, collateralTokens[1]);
    }

    function testGetCollateralTokenPriceFeed() public {
        address ethPriceFeed = zaxEngine.getCollateralTokensPriceFeed(weth);
        assertEq(ethPriceFeed, ethUsdPriceFeed);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = zaxEngine.getAccountInformation(USER);
        uint256 expectedCollateralValue = zaxEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(zaxEngine), AMOUNT_COLLATERAL);
        zaxEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = zaxEngine.getUserCollateral(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(zaxEngine), AMOUNT_COLLATERAL);
        zaxEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = zaxEngine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = zaxEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

     ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndmintZax {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = zaxEngine.getHealthFactor(USER);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }
      function testHealthFactorCanGoBelowOne() public depositedCollateralAndmintZax {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Rememeber, we need $150 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = zaxEngine.getHealthFactor(USER);
        // $180 collateral / 200 debt = 0.9
        assert(userHealthFactor == 0.9 ether);
    }


    /// modifiers
     modifier depositedCollateral() {
        vm.startPrank(USER);
        // vm.deal(USER,AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(zaxEngine), AMOUNT_COLLATERAL);
        zaxEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndmintZax() {
        vm.startPrank(USER);
        // vm.deal(USER,AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(zaxEngine), AMOUNT_COLLATERAL);
        zaxEngine.depositCollateralAndMintZax(weth, AMOUNT_COLLATERAL, AMOUNT_ZAX);
        // zaxEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier mintZax() {
        vm.startPrank(USER);
        zaxEngine.mintZax(AMOUNT_ZAX);
        vm.stopPrank();
        _;
    }

}

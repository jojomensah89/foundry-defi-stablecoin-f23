// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Zax} from "../../src/Zax.sol";
import {ZaxEngine} from "../../src/ZaxEngine.sol";
import {DeployZax} from "../../script/DeployZax.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

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
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALNCE = 100 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        deployer = new DeployZax();
        (zax, zaxEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFee, weth, wbtc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALNCE);
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

    modifier depositedCollateral() {
        vm.startPrank(USER);
        // vm.deal(USER,AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(zaxEngine), AMOUNT_COLLATERAL);
        zaxEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

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

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalZaxMinted, uint256 collateralValueInUsd) = zaxEngine.getAccountInformation(USER);

        uint256 expectedTotalZaxMinted = 0;
        uint256 expectedDepositAmount = zaxEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalZaxMinted, expectedTotalZaxMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // deposit Collateral a


    /// Getter Functions

    function testZaxContractAddress() public {
        assertEq(address(zax), address(zaxEngine.getZaxContractAddress()));
    }

    function testLiquidationThreshold() public {
        assertEq(zaxEngine.getLiquidationThreshold(), LIQUIDATION_THRESHOLD);
    }
}

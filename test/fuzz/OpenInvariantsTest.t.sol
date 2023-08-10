// SPDX-License-Identifier: MIT

// // Have our invariant aka properties

// // What are invariants?

// //1. The total supply of zax should be less than the total value of collateral

// //2. Getter view functions should never revert -  evergreen invariant

pragma solidity ^0.8.13;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {Zax} from "../../src/Zax.sol";
// import {ZaxEngine} from "../../src/ZaxEngine.sol";
// import {DeployZax} from "../../script/DeployZax.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployZax deployer;
//     ZaxEngine zaxEngine;
//     Zax zax;
//     HelperConfig helperConfig;
//     address ethUsdPriceFeed;
//     address weth;
//     address btcUsdPriceFee;
//     address wbtc;

//     function setUp() public {
//         deployer = new DeployZax();
//         (zax, zaxEngine, helperConfig) = deployer.run();
//         (ethUsdPriceFeed, btcUsdPriceFee, weth, wbtc,) = helperConfig.activeNetworkConfig();
//         targetContract(address(zaxEngine));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         // the protocol must always have more collateral than zax minted
//         // get the value of all the collateral in the protocol
//         // compare it to all the debt (zax)

//         uint256 totalSupply = zax.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(zaxEngine));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(zaxEngine));

//         uint256 wethValue = zaxEngine.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = zaxEngine.getUsdValue(wbtc, totalWbtcDeposited);
//         uint256 totalCollateralValueInUsd = wethValue + wbtcValue;

//         console.log("weth value:", wethValue);
//         console.log("wbtc value:", wbtcValue);
//         console.log(" totalCollateralValueInUsd:", totalCollateralValueInUsd);
//         console.log(" totalSupply:", totalSupply);

//         assert(totalCollateralValueInUsd >= totalSupply);
//     }
// }

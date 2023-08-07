// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Zax} from "../src/Zax.sol";
import {ZaxEngine} from "../src/ZaxEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployZax is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (Zax, ZaxEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        Zax zax = new Zax();

        ZaxEngine zaxEngine = new ZaxEngine(tokenAddresses,priceFeedAddresses,address(zax));

        zax.transferOwnership(address(zaxEngine));
        vm.stopBroadcast();

        return (zax, zaxEngine, helperConfig);
    }
}

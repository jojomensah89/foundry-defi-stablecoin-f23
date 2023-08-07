// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed; // ETH/USD priceFeed address
        address wbtcUsdPriceFeed; // BTC/USD priceFeed address
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    //constants
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 SEPOLIA_CHAIN_ID = 11155111;
    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // get price feed address for anvil
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        // deploy the contract
        vm.startBroadcast();

        MockV3Aggregator ethPriceFeed = new MockV3Aggregator(DECIMALS ,ETH_USD_PRICE);

        ERC20Mock wethMock = new ERC20Mock("WETH","WETH",msg.sender,1000e8);

        MockV3Aggregator btcPriceFeed = new MockV3Aggregator(DECIMALS ,BTC_USD_PRICE);

        ERC20Mock wbtcMock = new ERC20Mock("WBTC","WBTC",msg.sender,1000e8);

        vm.stopBroadcast();

        // return the mock address
        return NetworkConfig({
            wethUsdPriceFeed: address(ethPriceFeed),
            wbtcUsdPriceFeed: address(btcPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}

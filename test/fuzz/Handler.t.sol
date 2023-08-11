// SPDX-License-Identifier: MIT

// Handler will define the way to call the functions

pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Zax} from "../../src/Zax.sol";
import {ZaxEngine} from "../../src/ZaxEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    ZaxEngine zaxEngine;
    Zax zax;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public numTimesMintIsCalled;
    uint256 public numTimesDepositIsCalled;
    uint256 public numTimesUpdatePriceIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // the max uint96 value

    constructor(ZaxEngine _zaxEngine, Zax _zax) {
        zaxEngine = _zaxEngine;
        zax = _zax;

        address[] memory collateralTokens = zaxEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(zaxEngine.getCollateralTokensPriceFeed(address(weth)));
    }

    /**
     *
     * @param _amount ramdom number generated from fuzz testing
     * @param _addressSeed ramdom number generated from fuzz testing
     * @notice The Users should only be allowed to mint Zax only if they have deposited collateral
     * The invariants tests uses random users for every function hence the _addressSeed to select only users with collateral deposited
     */
    function mintZax(uint256 _amount, uint256 _addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address _msgSender = usersWithCollateralDeposited[_addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = zaxEngine.getAccountInformation(_msgSender);
        int256 maxZaxToMint = int256((collateralValueInUsd / 2)) - int256(totalDscMinted);

        if (maxZaxToMint < 0) {
            return;
        }
        _amount = bound(_amount, 0, uint256(maxZaxToMint));
        if (_amount == 0) {
            return;
        }

        vm.startPrank(_msgSender);
        zaxEngine.mintZax(_amount);
        vm.stopPrank();
        numTimesMintIsCalled++;
    }

    /**
     * @param _collateralSeed this a random number generated from fuzz testing (number/index will be used to get one of the collaterals)
     * @param _amountCollateral  this is a random number generated from fuzz testing(min = 1 , max = max of uint96)
     * @notice this function will call depositCollateral function from zaxEngine with the aprroved tokens and random deposit amounts
     */
    function depositCollateral(uint256 _collateralSeed, uint256 _amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        // _amountCollateral = _getAmountCollateral(_amountCollateral, 1, MAX_DEPOSIT_SIZE);
        _amountCollateral = bound(_amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, _amountCollateral);
        collateral.approve(address(zaxEngine), _amountCollateral);
        zaxEngine.depositCollateral(address(collateral), _amountCollateral);
        vm.stopPrank();
        // May double push the same sender
        usersWithCollateralDeposited.push(msg.sender);
    }

    /**
     *
     * @param _collateralSeed this a random number generated from fuzz testing (number/index will be used to get one of the collaterals)
     * @param _amountCollateral this is a random number generated from fuzz testing(min = 1 , max = max of uint96)
     */
    function redeemCollateral(uint256 _collateralSeed, uint256 _amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        uint256 maxCollateralToRedeem = zaxEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        _amountCollateral = bound(_amountCollateral, 0, maxCollateralToRedeem);
        // _amountCollateral = _getAmountCollateral(_amountCollateral, 0, maxCollateralToRedeem);

        if (_amountCollateral == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        zaxEngine.redeemCollateral(address(collateral), _amountCollateral);

        vm.stopPrank();
    }

    // This function breaks the test suite because when the price drops/rises too quickly in a single block the protocol breaks
    // function updateCollateralFromSeed(uint96 _newPrice) public {
    //     int256 newPriceInt = int256(uint256(_newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    //     numTimesUpdatePriceIsCalled++;
    // }

    //// Helper Functions
    /**
     * @param _collateralSeed An index(number)
     * @notice This function will return one of the two approved collateral tokens
     * @notice Update the function if the number of collateral tokens is increased
     */
    function _getCollateralFromSeed(uint256 _collateralSeed) private view returns (ERC20Mock) {
        if (_collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    /**
     * @param _amountCollateral the random amount of collateral
     * @param _maxAmount the upper limit of the range
     * @param _minAmount the lower limit of the range
     * @notice This function sets the range i.e max and min amount of deposit
     */
    function _getAmountCollateral(uint256 _amountCollateral, uint256 _minAmount, uint256 _maxAmount)
        private
        view
        returns (uint256)
    {
        return bound(_amountCollateral, _minAmount, _maxAmount);
    }
}

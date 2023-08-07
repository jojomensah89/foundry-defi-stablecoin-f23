// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Zax Stablecoin
 * @author Ebenezer Jojo Mensah
 * Collateral: Exogenous(ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * @notice This is the contract meant to be governed by DSCEngine/ZaxEngine. This contract is just the ERC20 implementation of our stablecoin system
 */

contract Zax is ERC20Burnable, Ownable {
    error Zax__MustBeMoreThanZero();
    error Zax__BurnAmountExceedsBalance();
    error Zax__NotZeroAddress();

    constructor() ERC20("Zax", "ZAX") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 ownerBalance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert Zax__MustBeMoreThanZero();
        }
        if (ownerBalance < _amount) {
            revert Zax__BurnAmountExceedsBalance();
        }

        // Super keyword represents ERC20Burnable. We are overriding the original burn function from ERC20Burnable
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert Zax__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert Zax__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}

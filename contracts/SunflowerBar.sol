pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// SunflowerBar is the coolest bar in town. You come in with some Sunflower, and leave with more! The longer you stay, the more Sunflower you get.
//
// This contract handles swapping to and from xSunflower, SunflowerSwap's staking token.
contract SunflowerBar is ERC20("SunflowerBar", "xSFR"){
    using SafeMath for uint256;
    IERC20 public sunflower;

    // Define the Sunflower token contract
    constructor(IERC20 _sunflower) public {
        sunflower = _sunflower;
    }

    // Enter the bar. Pay some SFRs. Earn some shares.
    // Locks Sunflower and mints xSunflower
    function enter(uint256 _amount) public {
        // Gets the amount of Sunflower locked in the contract
        uint256 totalSunflower = sunflower.balanceOf(address(this));
        // Gets the amount of xSunflower in existence
        uint256 totalShares = totalSupply();
        // If no xSunflower exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalSunflower == 0) {
            _mint(msg.sender, _amount);
        } 
        // Calculate and mint the amount of xSunflower the Sunflower is worth. The ratio will change overtime, as xSunflower is burned/minted and Sunflower deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount.mul(totalShares).div(totalSunflower);
            _mint(msg.sender, what);
        }
        // Lock the Sunflower in the contract
        sunflower.transferFrom(msg.sender, address(this), _amount);
    }

    // Leave the bar. Claim back your SFRs.
    // Unclocks the staked + gained Sunflower and burns xSunflower
    function leave(uint256 _share) public {
        // Gets the amount of xSunflower in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Sunflower the xSunflower is worth
        uint256 what = _share.mul(sunflower.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        sunflower.transfer(msg.sender, what);
    }
}

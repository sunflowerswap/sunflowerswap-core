pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./uniswapv2/interfaces/IUniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";

// SunflowerMaker is SunflowerMain's left hand and kinda a wizard. He can cook up Sunflower from pretty much anything!
//
// This contract handles "serving up" rewards for xSunflower holders by trading tokens collected from fees for Sunflower.

contract SunflowerMaker {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public factory;
    address public bar;
    address public sunflower;
    address public weth;
    address public burnt;

    uint256 public totalBurntSFR;
    uint256 public totalRewardSFR;

    uint256 public rewardPoint;
    uint256 public burntPoint;

    uint256 public constant maxBurntSFR = 32222223000000000000000;

    constructor(IUniswapV2Factory _factory, address _bar, address _sunflower, address _weth) public {
        factory = _factory;
        sunflower = _sunflower;
        bar = _bar;
        weth = _weth;
        burnt = address(1);
        rewardPoint = 5;
        burntPoint = 5;
    }

    function convert(address token0, address token1) public {
        // At least we try to make front-running harder to do.
        require(msg.sender == tx.origin, "do not convert from contract");
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        pair.transfer(address(pair), pair.balanceOf(address(this)));
        pair.burn(address(this));
        // First we convert everything to WETH
        uint256 wethAmount = _toWETH(token0) + _toWETH(token1);
        // Then we convert the WETH to Sunflower
        _toSFR(wethAmount);
    }

    // Converts token passed as an argument to WETH
    function _toWETH(address token) internal returns (uint256) {
        // If the passed token is Sunflower, don't convert anything
        if (token == sunflower) {
            uint amount = IERC20(token).balanceOf(address(this));
            _safeTransfer(token, bar, amount.mul(rewardPoint).div(10));
            totalRewardSFR = totalRewardSFR.add(amount.mul(rewardPoint).div(10));
            uint256 burntAmount = _getBurntAmount(amount);
            if(burntAmount > 0){
                _safeTransfer(token, burnt, burntAmount);
                totalBurntSFR = totalBurntSFR.add(burntAmount);
            }
            return 0;
        }
        // If the passed token is WETH, don't convert anything
        if (token == weth) {
            uint amount = IERC20(token).balanceOf(address(this));
            _safeTransfer(token, factory.getPair(weth, sunflower), amount);
            return amount;
        }
        // If the target pair doesn't exist, don't convert anything
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token, weth));
        if (address(pair) == address(0)) {
            return 0;
        }
        // Choose the correct reserve to swap from
        (uint reserve0, uint reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        (uint reserveIn, uint reserveOut) = token0 == token ? (reserve0, reserve1) : (reserve1, reserve0);
        // Calculate information required to swap
        uint amountIn = IERC20(token).balanceOf(address(this));
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        uint amountOut = numerator / denominator;
        (uint amount0Out, uint amount1Out) = token0 == token ? (uint(0), amountOut) : (amountOut, uint(0));
        // Swap the token for WETH
        _safeTransfer(token, address(pair), amountIn);
        pair.swap(amount0Out, amount1Out, factory.getPair(weth, sunflower), new bytes(0));
        return amountOut;
    }

    // Converts WETH to Sunflower
    function _toSFR(uint256 amountIn) internal {
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(weth, sunflower));
        // Choose WETH as input token
        (uint reserve0, uint reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        (uint reserveIn, uint reserveOut) = token0 == weth ? (reserve0, reserve1) : (reserve1, reserve0);
        // Calculate information required to swap
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        uint amountOut = numerator / denominator;
        (uint amount0Out, uint amount1Out) = token0 == weth ? (uint(0), amountOut) : (amountOut, uint(0));
        // Swap WETH for Sunflower
        pair.swap(amount0Out, amount1Out, address(this), new bytes(0));

        uint balance =  IERC20(sunflower).balanceOf(address(this));

        uint amountOutBar = balance.mul(rewardPoint).div(10);
        _safeTransfer(sunflower, bar, amountOutBar);
        totalRewardSFR = totalRewardSFR.add(amountOutBar);
        uint256 burntAmount = _getBurntAmount(balance);
        if(burntAmount > 0){
            _safeTransfer(sunflower, burnt, burntAmount);
            totalBurntSFR = totalBurntSFR.add(burntAmount);
        }
    }

    // Wrapper for safeTransfer
    function _safeTransfer(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function _getBurntAmount(uint256 amount) internal returns(uint256) {
        if(totalBurntSFR >= maxBurntSFR){
            if(burntPoint > 0){
                burntPoint = 0;
                rewardPoint = 10;
            }
            return 0;
        }
        if(burntPoint > 0){
            uint256 burntAmount = amount.mul(burntPoint).div(10);
            if(burntAmount.add(totalBurntSFR) >= maxBurntSFR){
                return burntAmount.add(totalBurntSFR).sub(maxBurntSFR);
            }else{
                return burntAmount;
            }
        }
        return 0;
    }
}

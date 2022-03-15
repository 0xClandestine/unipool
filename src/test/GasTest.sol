// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

import "../Unipool.sol";
import {UnipoolFactory} from "../UnipoolFactory.sol";


import "./test.sol";

contract MockContract is ERC20 {
    constructor(
        string memory name, 
        string memory symbol
    ) ERC20(name, symbol, 18) {}

    function mint(address guy, uint256 wad) public {
        _mint(guy, wad);
    }
}

contract SwapGasTest is DSTest {

    UnipoolFactory factory;
    MockContract baseToken;
    MockContract quoteToken;
    Unipool pair;

    uint baseAmount = 5e18;
    uint quoteAmount = 10e18;
    uint swapAmount = 1e18;
    uint expectedOutputAmount = 1662497915624478906;

    function setUp() public {
        factory = new UnipoolFactory();
        baseToken = new MockContract("Base Token", "BASE");
        quoteToken = new MockContract("Quote Token", "QUOTE");
        // Pair needs initialized after deployment
        pair = Unipool(factory.createPair(address(baseToken), address(quoteToken)));
        baseToken.mint(address(this), 1e27);
        quoteToken.mint(address(this), 1e27);

        baseToken.transfer(address(pair), baseAmount);
        quoteToken.transfer(address(pair), quoteAmount);
        pair.mint(address(this));

    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint amountIn, 
        uint reserveIn, 
        uint reserveOut
    ) internal pure returns (uint amountOut) {
        uint amountInWithFee = amountIn * (9975);
        amountOut = amountInWithFee * reserveOut / (reserveIn * 10000 + amountInWithFee);
    }

    function testSwapGas() public {
        baseToken.transfer(address(pair), swapAmount);
        uint amountOut = getAmountOut(swapAmount, baseAmount, quoteAmount);
        pair.swap(0, amountOut, address(this), "");
    }
}

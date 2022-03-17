// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import {ERC20}          from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {UnipoolFactory} from "../UnipoolFactory.sol";
import {UnipoolRouter}  from "../UnipoolRouter.sol";
import {Unipool}        from "../Unipool.sol";
import {DSTest}         from "./utils/test.sol";

import {Strings}        from "@openzeppelin/contracts/utils/Strings.sol";

contract MockERC20 is ERC20 {    
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}
    function mint(address guy, uint256 wad) public {_mint(guy, wad);}
}

interface IUniswapV2Pair {
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function initialize(address, address, uint) external;
    function implementation() external view returns (address);
}

contract UnipoolRouterTest is DSTest {

    UnipoolFactory factory;
    UnipoolRouter router;
    MockERC20 baseToken;
    MockERC20 quoteToken;
    Unipool pair;

    function setUp() public {
        // deploy factory and router
        factory = new UnipoolFactory();
        router = new UnipoolRouter(address(factory), factory.implementation(), address(factory));

        // deploy some test tokens
        baseToken = new MockERC20("Base Token", "BASE");
        quoteToken = new MockERC20("Quote Token", "QUOTE");
        
        // create pool for test tokens
        pair = Unipool(factory.createPair(address(baseToken), address(quoteToken))); 
        
        // mint this address some test tokens
        baseToken.mint(address(this), 1e27);    // 1,000,000,000 tokens
        quoteToken.mint(address(this), 1e27);   // 1,000,000,000 tokens
    }

    function addLiquidity(uint baseAmount, uint quoteAmount) internal {
        baseToken.transfer(address(pair), baseAmount);
        quoteToken.transfer(address(pair), quoteAmount);
        pair.mint(address(this));
    }

    function testSwapExactTokensForTokens() public {
        addLiquidity(100e18, 1000e18);

        address[] memory path = new address[](2);
        path[0] = address(quoteToken);
        path[1] = address(baseToken);

        quoteToken.approve(address(router), type(uint256).max);

        uint256[] memory amountsOut = router.swapExactTokensForTokens(
            1e18, 
            router.getAmountOut(1e18, 1000e18, 100e18), 
            path, 
            address(this), 
            block.timestamp
        );

        uint256 amountOut = amountsOut[amountsOut.length - 1];

        require(amountOut == 99650598527968351, Strings.toString(amountOut));
    }
}

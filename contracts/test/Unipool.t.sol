// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {UnipoolFactory} from "../UnipoolFactory.sol";
import "../Unipool.sol"; // where my custahs at
import "./utils/test.sol";

contract MockERC20 is ERC20 {    
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}
    function mint(address guy, uint256 wad) public {
        _mint(guy, wad);
    }
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
}

contract UnipoolTest is DSTest {

    UnipoolFactory factory;
    MockERC20 baseToken;
    MockERC20 quoteToken;
    Unipool pair;

    function setUp() public {
        factory = new UnipoolFactory();
        baseToken = new MockERC20("Base Token", "BASE");
        quoteToken = new MockERC20("Quote Token", "QUOTE");
        // Pair needs to be initialized after deployment
        pair = Unipool(factory.createPair(address(baseToken), address(quoteToken)));
        //mint tokens to create lp to testing 'this' contract
        baseToken.mint(address(this), 1e27);
        quoteToken.mint(address(this), 1e27);
    }

    function addLiquidity(uint baseAmount, uint quoteAmount) internal {
        baseToken.transfer(address(pair), baseAmount);
        quoteToken.transfer(address(pair), quoteAmount);
        pair.mint(address(this));
    }

    function testMint() public {
        uint baseAmount = 1e18;
        uint quoteAmount = 4e18;
        uint expectedLiquidity = 2e18;

        addLiquidity(baseAmount, quoteAmount);

        (uint baseReserves, uint quoteReserves,) = pair.getReserves();
        require(pair.totalSupply() == expectedLiquidity, "make sure pair supply is equal to expected liquidity");
        require(pair.balanceOf(address(this)) == expectedLiquidity - 10_000, "make sure pair balance of this contract is equal to expected liquidity minus MIN_LIQ");
        require(baseToken.balanceOf(address(pair)) == baseAmount, "make sure base token balance of pair is equal to base amount");
        require(quoteToken.balanceOf(address(pair)) == quoteAmount, "make sure quote token balance of pair is equal to quote amount");
        require(baseReserves == baseAmount, "make sure base reserves equal base amount");
        require(quoteReserves == quoteAmount, "make sure quote reserves equal quote amount");
    }

    function testSwapBaseToken() public {
        uint baseAmount = 5e18;
        uint quoteAmount = 10e18;
        uint swapAmount = 1e18;
        uint expectedOutputAmount = 1662497915624478906;

        addLiquidity(baseAmount, quoteAmount);

        baseToken.transfer(address(pair), swapAmount);
        
        pair.swap(0, expectedOutputAmount, address(this), "");

        (uint baseReserves, uint quoteReserves,) = pair.getReserves();
        require(baseReserves == baseAmount + swapAmount, "make sure base reserves equal base amount + swap amount");
        require(quoteReserves == quoteAmount - expectedOutputAmount, "make sure quote reserves equal quote amount - expected output");
        require(baseToken.balanceOf(address(pair)) == baseAmount + swapAmount, "make sure base token balance of this contract equals base amount + swap amount");
        require(quoteToken.balanceOf(address(pair)) == quoteAmount - expectedOutputAmount, "make sure quote token balance of this contract equals quote amount - expected output");
        // // expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount).sub(swapAmount))
        // // expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount).add(expectedOutputAmount))
    }


    function testSwapQuoteToken() public {
        uint baseAmount = 5e18;
        uint quoteAmount = 10e18;
        uint swapAmount = 1e18;
        uint expectedOutputAmount = 453305446940074565;

        addLiquidity(baseAmount, quoteAmount);

        quoteToken.transfer(address(pair), swapAmount);

        pair.swap(expectedOutputAmount, 0, address(this), "");

        (uint baseReserves, uint quoteReserves,) = pair.getReserves();
        require(baseReserves == baseAmount - expectedOutputAmount);
        require(quoteReserves == quoteAmount + swapAmount);
        require(baseToken.balanceOf(address(pair)) == baseAmount - expectedOutputAmount);
        require(quoteToken.balanceOf(address(pair)) == quoteAmount + swapAmount);
        // expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount).add(expectedOutputAmount))
        // expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount).sub(swapAmount))
    }

    function testBurn() public {

        uint baseAmount = 3e18;
        uint quoteAmount = 3e18;
        uint expectedLiquidity = 3e18;

        addLiquidity(baseAmount, quoteAmount);

        pair.transfer(address(pair), expectedLiquidity - 10_000);

        pair.burn(address(this));

        require(pair.balanceOf(address(this)) == 0);
        require(pair.totalSupply() == 10_000);
        require(baseToken.balanceOf(address(pair)) == 10_000);
        require(quoteToken.balanceOf(address(pair)) == 10_000);
        uint totalSupplyToken0 = baseToken.totalSupply();
        uint totalSupplyToken1 = quoteToken.totalSupply();
        require(baseToken.balanceOf(address(this)) == totalSupplyToken0 - 10_000);
        require(quoteToken.balanceOf(address(this)) == totalSupplyToken1 - 10_000);
    }
}


//   it('price{0,1}CumulativeLast', async () => {
//     const token0Amount = expandTo18Decimals(3)
//     const token1Amount = expandTo18Decimals(3)
//     await addLiquidity(token0Amount, token1Amount)

//     const blockTimestamp = (await pair.getReserves())[2]
//     await mineBlock(provider, blockTimestamp + 1)
//     await pair.sync(overrides)

//     const initialPrice = encodePrice(token0Amount, token1Amount)
//     expect(await pair.price0CumulativeLast()).to.eq(initialPrice[0])
//     expect(await pair.price1CumulativeLast()).to.eq(initialPrice[1])
//     expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 1)

//     const swapAmount = expandTo18Decimals(3)
//     await token0.transfer(pair.address, swapAmount)
//     await mineBlock(provider, blockTimestamp + 10)
//     // swap to a new price eagerly instead of syncing
//     await pair.swap(0, expandTo18Decimals(1), wallet.address, '0x', overrides) // make the price nice

//     expect(await pair.price0CumulativeLast()).to.eq(initialPrice[0].mul(10))
//     expect(await pair.price1CumulativeLast()).to.eq(initialPrice[1].mul(10))
//     expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 10)

//     await mineBlock(provider, blockTimestamp + 20)
//     await pair.sync(overrides)

//     const newPrice = encodePrice(expandTo18Decimals(6), expandTo18Decimals(2))
//     expect(await pair.price0CumulativeLast()).to.eq(initialPrice[0].mul(10).add(newPrice[0].mul(10)))
//     expect(await pair.price1CumulativeLast()).to.eq(initialPrice[1].mul(10).add(newPrice[1].mul(10)))
//     expect((await pair.getReserves())[2]).to.eq(blockTimestamp + 20)
//   })

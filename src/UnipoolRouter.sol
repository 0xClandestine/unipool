// SPDX-License-Identifier: GPLv3
pragma solidity >=0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IERC20.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

import "./libraries/UnipoolLibrary.sol";

interface IERC20PermitAllowed {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract UnipoolRouter {

    address public immutable factory;
    address public immutable implementation;
    address public immutable WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    constructor(
        address _factory, 
        address _implementation, 
        address _WETH
    ) {
        factory = _factory;
        implementation = _implementation;
        WETH = _WETH;
    }

    receive() external payable {
        // only accept ETH via fallback from the WETH contract
        assert(msg.sender == WETH); 
    }

    /* -------------------------------------------------------------------------- */
    /*                             ADD LIQUIDITY LOGIC                            */
    /* -------------------------------------------------------------------------- */

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // 1) store factory in memory to avoid a few SLOADS
        address _factory = factory;
        // 2) create the pair if it doesn"t exist yet
        if (IUniswapV2Factory(_factory).getPair(tokenA, tokenB) == address(0)) IUniswapV2Factory(_factory).createPair(tokenA, tokenB);
        // 3) fetch reserves and store in memory to avoid a few SLOADS
        (uint reserveA, uint reserveB) = UnipoolLibrary.getReserves(_factory, implementation, tokenA, tokenB);
        
        if (reserveA + reserveB == 0) (amountA, amountB) = (amountADesired, amountBDesired);
        else {
            uint amountBOptimal = UnipoolLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UnipoolLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UnipoolLibrary.pairFor(factory, implementation, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = UnipoolLibrary.pairFor(factory, implementation, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UnipoolLibrary.pairFor(factory, implementation, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UnipoolLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB) {
        IUniswapV2Pair(UnipoolLibrary.pairFor(factory, implementation, tokenA, tokenB)).permit(
            msg.sender, 
            address(this), 
            approveMax ? type(uint).max : liquidity, 
            deadline, 
            v, 
            r, 
            s
        );
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH) {
        address pair = UnipoolLibrary.pairFor(factory, implementation, token, WETH);
        uint value = approveMax ? type(uint).max : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH) {
        address pair = UnipoolLibrary.pairFor(factory, implementation, token, WETH);
        uint value = approveMax ? type(uint).max : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 SWAP LOGIC                                 */
    /* -------------------------------------------------------------------------- */

    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint[] memory amounts, 
        address[] memory path, 
        address _to
    ) internal virtual {
        // unchecked orginally 
        unchecked {
            uint256 pathLength = path.length;
            address _implementation = implementation;
            for (uint i; i < pathLength - 1; ++i) {
                (address input, address output) = (path[i], path[i + 1]);
                (address token0,) = UnipoolLibrary.sortTokens(input, output);
                uint amountOut = amounts[i + 1];
                (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
                address to = i < path.length - 2 ? UnipoolLibrary.pairFor(factory, _implementation, output, path[i + 2]) : _to;
                IUniswapV2Pair(UnipoolLibrary.pairFor(factory, _implementation, input, output)).swap(
                    amount0Out, 
                    amount1Out, 
                    to, 
                    new bytes(0)
                );
            }
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint[] memory amounts) {
        unchecked {
            address _implementation = implementation;
            amounts = UnipoolLibrary.getAmountsOut(factory, _implementation, amountIn, path);
            require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
            TransferHelper.safeTransferFrom(
                path[0], 
                msg.sender, 
                UnipoolLibrary.pairFor(factory, _implementation, path[0], path[1]), amounts[0]
            );
            _swap(amounts, path, to);
        }
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint[] memory amounts) {
        address _implementation = implementation;
        amounts = UnipoolLibrary.getAmountsIn(factory, implementation, amountOut, path);
        require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], 
            msg.sender, 
            UnipoolLibrary.pairFor(factory, _implementation, path[0], path[1]), 
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external payable ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, "INVALID_PATH");
        address _implementation = implementation;
        amounts = UnipoolLibrary.getAmountsOut(factory, _implementation, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UnipoolLibrary.pairFor(factory, _implementation, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(    
        uint amountOut, 
        uint amountInMax, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) public ensure(deadline) returns (uint[] memory amounts) {
        // Store the strings w
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        address _implementation = implementation;
        amounts = UnipoolLibrary.getAmountsIn(factory, _implementation, amountOut, path);
        //amountInMax > amounts[0] ] golfin?
        require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, UnipoolLibrary.pairFor(
            factory, 
            _implementation, 
            path[0], 
            path[1]), 
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) public ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        address _implementation = implementation;
        amounts = UnipoolLibrary.getAmountsOut(factory, _implementation, amountIn, path);
        //amountOutMin > amounts[amounts.length - 1 ] golfin?
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], 
            msg.sender, 
            UnipoolLibrary.pairFor(factory, _implementation, path[0], path[1]), 
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint amountOut, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external payable ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, "INVALID_PATH");
        address _implementation = implementation;
        amounts = UnipoolLibrary.getAmountsIn(factory, _implementation, amountOut, path);
        require(amounts[0] <= msg.value, "EXCESSIVE_INPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UnipoolLibrary.pairFor(factory, _implementation, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    /* -------------------------------------------------------------------------- */
    /*                              PERMIT SWAP LOGIC                             */
    /* -------------------------------------------------------------------------- */

    function swapExactTokensForTokensUsingPermit(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        IERC20Permit(path[0]).permit(msg.sender, address(this), amountIn, deadline, v, r, s);
        amounts = swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

    function swapExactTokensForTokensUsingPermitAllowed(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);
        amounts = swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

    function swapTokensForExactTokensUsingPermit(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        IERC20Permit(path[0]).permit(msg.sender, address(this), amountInMax, deadline, v, r, s);
        amounts = swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline);
    }

    function swapTokensForExactTokensUsingPermitAllowed(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);
        amounts = swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline);
    }

    function swapTokensForExactETHUsingPermit(    
        uint amountOut, 
        uint amountInMax, 
        address[] calldata path, 
        address to, 
        uint deadline, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        IERC20Permit(path[0]).permit(msg.sender, address(this), amountInMax, deadline, v, r, s);
        amounts = swapTokensForExactETH(amountOut, amountInMax, path, to, deadline);
    }

    function swapTokensForExactETHUsingPermitAllowed(    
        uint amountOut, 
        uint amountInMax, 
        address[] calldata path, 
        address to, 
        uint deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);
        amounts = swapTokensForExactETH(amountOut, amountInMax, path, to, deadline);
    }

    function swapExactTokensForETHUsingPermit(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        IERC20Permit(path[0]).permit(msg.sender, address(this), amountIn, deadline, v, r, s);
        amounts = swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
    }

    function swapExactTokensForETHUsingPermitAllowed(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);
        amounts = swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
    }

    /* -------------------------------------------------------------------------- */
    /*               SWAP (supporting fee-on-transfer tokens) LOGIC               */
    /* -------------------------------------------------------------------------- */
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path, 
        address _to
    ) internal virtual {
        address _implementation = implementation;
        // uint256 pathLength = path.length;

        // Cache the length, ++i for gas golfing?
        for (uint i; i < path.length - 1; i++) {
            
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UnipoolLibrary.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UnipoolLibrary.pairFor(factory, _implementation, input, output));

            uint amountOutput;
            
            { // scope to avoid stack too deep errors
                (uint reserve0, uint reserve1,) = pair.getReserves();
                (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountOutput = UnipoolLibrary.getAmountOut(
                    IERC20(input).balanceOf(address(pair)) - reserveInput, 
                    reserveInput, 
                    reserveOutput
                );
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UnipoolLibrary.pairFor(factory, _implementation, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, UnipoolLibrary.pairFor(factory, implementation,path[0], path[1]), amountIn);
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(IERC20(path[path.length - 1]).balanceOf(to) - (balanceBefore) >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable ensure(deadline) {
        require(path[0] == WETH, "INVALID_PATH");
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(UnipoolLibrary.pairFor(factory, implementation, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(IERC20(path[path.length - 1]).balanceOf(to) - (balanceBefore) >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) {
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        TransferHelper.safeTransferFrom(path[0], msg.sender, UnipoolLibrary.pairFor(factory, implementation, path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    /* -------------------------------------------------------------------------- */
    /*                              LIBRARY FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    function quote(uint amountA, uint reserveA, uint reserveB) public pure returns (uint amountB) {
        return UnipoolLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        return UnipoolLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure returns (uint amountIn) {
        return UnipoolLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        return UnipoolLibrary.getAmountsOut(factory, implementation, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view returns (uint[] memory amounts) {
        return UnipoolLibrary.getAmountsIn(factory, implementation, amountOut, path);
    }
}
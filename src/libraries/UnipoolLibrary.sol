// SPDX-License-Identifier: GPLv3
pragma solidity >=0.8.0;

interface Unipool {
    function getReserves() external view returns (
        uint112 baseReserves, 
        uint112 quoteReserves, 
        uint32 lastUpdate
    );
}

library UnipoolLibrary {
    // Taken from @rari-capital/solmate/src/utils/CREATE3.sol
    //--------------------------------------------------------------------------------//
    // Opcode     | Opcode + Arguments    | Description      | Stack View             //
    //--------------------------------------------------------------------------------//
    // 0x36       |  0x36                 | CALLDATASIZE     | size                   //
    // 0x3d       |  0x3d                 | RETURNDATASIZE   | 0 size                 //
    // 0x3d       |  0x3d                 | RETURNDATASIZE   | 0 0 size               //
    // 0x37       |  0x37                 | CALLDATACOPY     |                        //
    // 0x36       |  0x36                 | CALLDATASIZE     | size                   //
    // 0x3d       |  0x3d                 | RETURNDATASIZE   | 0 size                 //
    // 0x34       |  0x34                 | CALLVALUE        | value 0 size           //
    // 0xf0       |  0xf0                 | CREATE           | newContract            //
    //--------------------------------------------------------------------------------//
    // Opcode     | Opcode + Arguments    | Description      | Stack View             //
    //--------------------------------------------------------------------------------//
    // 0x67       |  0x67XXXXXXXXXXXXXXXX | PUSH8 bytecode   | bytecode               //
    // 0x3d       |  0x3d                 | RETURNDATASIZE   | 0 bytecode             //
    // 0x52       |  0x52                 | MSTORE           |                        //
    // 0x60       |  0x6008               | PUSH1 08         | 8                      //
    // 0x60       |  0x6018               | PUSH1 18         | 24 8                   //
    // 0xf3       |  0xf3                 | RETURN           |                        //
    //--------------------------------------------------------------------------------//
    bytes internal constant PROXY_BYTECODE = hex"67_36_3d_3d_37_36_3d_34_f0_3d_52_60_08_60_18_f3";
    bytes32 internal constant PROXY_BYTECODE_HASH = keccak256(PROXY_BYTECODE);

    function uDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {assembly {z := div(x, y)}}

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(
        address tokenA, 
        address tokenB
    ) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/CREATE3.sol)
    function getDeployed(
        address deployer, 
        bytes32 salt
    ) internal pure returns (address) {
        address proxy = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xFF), deployer, salt, PROXY_BYTECODE_HASH)))));
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d6_94", proxy, hex"01")))));
    }

    // calculates the CREATE3 address for a pair without making any external calls
    function pairFor(
        address factory, 
        address tokenA, 
        address tokenB 
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = getDeployed(factory, keccak256(abi.encodePacked(token0, token1)));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(
        address factory, 
        address tokenA, 
        address tokenB
    ) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint baseReserves, uint quoteReserves,) = Unipool(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (baseReserves, quoteReserves) : (quoteReserves, baseReserves);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint amountA, 
        uint reserveA, 
        uint reserveB
    ) internal pure returns (uint amountB) {
        amountB = uDiv(amountA * reserveB, reserveA);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint amountIn, 
        uint reserveIn, 
        uint reserveOut
    ) internal pure returns (uint amountOut) {
        uint amountInWithFee = amountIn * (997);
        amountOut = uDiv(amountInWithFee * reserveOut, reserveIn * 1000 + amountInWithFee);
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint amountOut, 
        uint reserveIn, 
        uint reserveOut
    ) internal pure returns (uint amountIn) {
        amountIn = uDiv(reserveIn * amountOut * 1000, reserveOut - amountOut * 997) + 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                        SHOULD PROB BE UNCHECKED VVV                        */
    /* -------------------------------------------------------------------------- */

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address factory, 
        uint amountIn, 
        address[] memory path
    ) internal view returns (uint[] memory amounts) {
        unchecked {
            uint256 pathLength = path.length; // save gas
            
            amounts = new uint[](pathLength);
            amounts[0] = amountIn;
            
            for (uint i; i < pathLength - 1; ++i) {
                (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
                amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
            }
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address factory, 
        uint amountOut, 
        address[] memory path
    ) internal view returns (uint[] memory amounts) {
        unchecked {
            uint256 pathLength = path.length; // save gas

            amounts = new uint[](pathLength);
            amounts[pathLength - 1] = amountOut;
            
            for (uint i = pathLength - 1; i > 0; --i) {
                (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
                amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
            }
        }
    }
}

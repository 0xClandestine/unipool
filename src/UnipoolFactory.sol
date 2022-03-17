// SPDX-License-Identifier: GPLv3
pragma solidity >=0.8.0;

import "./Unipool.sol";

contract UnipoolFactory {

    mapping(address => mapping(address => address)) private _getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    address public implementation = address(new Unipool());

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        
        require(tokenA != tokenB, "UniswapV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2: ZERO_ADDRESS");
        require(_getPair[token0][token1] == address(0), "UniswapV2: PAIR_EXISTS"); // single check is sufficient

        pair = cloneDeterministic(implementation, keccak256(abi.encodePacked(token0, token1)));
        Unipool(pair).initialize(token0, token1, 25);
        
        _getPair[token0][token1] = pair;
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return _getPair[token0][token1];
    }
    
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    /* -------------------------------------------------------------------------- */
    /*                                CLONE LOGIC                                 */
    /* -------------------------------------------------------------------------- */

    function cloneDeterministic(address impl, bytes32 salt) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, impl))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }
}
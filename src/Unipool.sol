// SPDX-License-Identifier: GPLv3
pragma solidity >=0.8.0;

// ██    ██ ███    ██ ██ ██████   ██████   ██████  ██      
// ██    ██ ████   ██ ██ ██   ██ ██    ██ ██    ██ ██      
// ██    ██ ██ ██  ██ ██ ██████  ██    ██ ██    ██ ██      
// ██    ██ ██  ██ ██ ██ ██      ██    ██ ██    ██ ██      
//  ██████  ██   ████ ██ ██       ██████   ██████  ███████

import {ERC20}                      from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib}          from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {TransferHelper}             from "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract Unipool is ERC20("Unipool LP Token", "CLP", 18), ReentrancyGuardUpgradeable {

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event Mint(address indexed sender, uint256 baseAmount, uint256 quoteAmount);
    event Burn(address indexed sender, uint256 baseAmount, uint256 quoteAmount, address indexed to);
    
    event Swap(
        address indexed sender, 
        uint256 baseAmountIn, 
        uint256 quoteAmountIn, 
        uint256 baseAmountOut, 
        uint256 quoteAmountOut, 
        address indexed to
    );
     
    event Sync(uint112 baseReserves, uint112 quoteReserves);

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    // To avoid division by zero, there is a minimum number of liquidity tokens that always 
    // exist (but are owned by account zero). That number is BIPS_DIVISOR, ten thousand.
    uint256 internal constant PRECISION = 112;
    uint256 internal constant BIPS_DIVISOR = 10_000;

    /* -------------------------------------------------------------------------- */
    /*                                MUTABLE STATE                               */
    /* -------------------------------------------------------------------------- */

    address public base;
    address public quote;

    uint256 public swapFee;
    uint256 public basePriceCumulativeLast;
    uint256 public quotePriceCumulativeLast;
    
    uint112 private baseReserves;   
    uint112 private quoteReserves;
    uint32  private lastUpdate;

    function getReserves() public view returns (uint112 _baseReserves, uint112 _quoteReserves, uint32 _lastUpdate) {
        (_baseReserves, _quoteReserves, _lastUpdate) = (baseReserves, quoteReserves, lastUpdate);
    }

    /* -------------------------------------------------------------------------- */
    /*                               INITIALIZATION                               */
    /* -------------------------------------------------------------------------- */

    error INITIALIZED();

    // called once by the factory at time of deployment
    function initialize(
        address _base, 
        address _quote, 
        uint256 _swapFee
    ) external {
        if (swapFee > 0) revert INITIALIZED();
        (base, quote, swapFee) = (_base, _quote, _swapFee);
        _mint(address(0), BIPS_DIVISOR); 

        __ReentrancyGuard_init();

    }

    error BALANCE_OVERFLOW();

    /// @notice update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 baseBalance, 
        uint256 quoteBalance, 
        uint112 _baseReserves, 
        uint112 _quoteReserves
    ) private {
        unchecked {
            // 1) revert if both balances are greater than 2**112
            if (baseBalance > type(uint112).max && quoteBalance > type(uint112).max) revert BALANCE_OVERFLOW();
            // 2) store current time in memory (mod 2**32 to prevent DoS in 20 years)
            uint32 timestampAdjusted = uint32(block.timestamp % 2**32);
            // 3) store elapsed time since last update
            uint256 timeElapsed = timestampAdjusted - lastUpdate; 
            // 4) if oracle info hasn"t been updated this block, and there's liquidity, update TWAP variables
            if (timeElapsed > 0 && _baseReserves != 0 && _quoteReserves != 0) {
                basePriceCumulativeLast += (uint(_quoteReserves) << PRECISION) / _baseReserves * timeElapsed;
                quotePriceCumulativeLast += (uint(_baseReserves) << PRECISION) / _quoteReserves * timeElapsed;
            }
            // 5) sync reserves (make them match balances)
            (baseReserves, quoteReserves, lastUpdate) = (uint112(baseBalance), uint112(quoteBalance), timestampAdjusted);
            // 6) emit event since mutable storage was updated
            emit Sync(baseReserves, quoteReserves);
        }
    }

    error INSUFFICIENT_LIQUIDITY_MINTED();

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        // 1) store any variables used more than once in memory to avoid SLOAD"s
        (uint112 _baseReserves, uint112 _quoteReserves,) = getReserves();
        uint256 baseBalance = ERC20(base).balanceOf(address(this));
        uint256 quoteBalance = ERC20(quote).balanceOf(address(this));
        uint256 baseAmount = baseBalance - (_baseReserves);
        uint256 quoteAmount = quoteBalance - (_quoteReserves);
        uint256 _totalSupply = totalSupply;
        // 2) if lp token total supply is equal to BIPS_DIVISOR (1,000 wei), 
        // amountOut (liquidity) is equal to the root of k minus BIPS_DIVISOR  
        if (_totalSupply == BIPS_DIVISOR) liquidity = FixedPointMathLib.sqrt(baseAmount * quoteAmount) - BIPS_DIVISOR; 
        else liquidity = min(uDiv(baseAmount * _totalSupply, _baseReserves), uDiv(quoteAmount * _totalSupply, _quoteReserves));
        // 3) revert if Lp tokens out is equal to zero
        if (liquidity == 0) revert INSUFFICIENT_LIQUIDITY_MINTED();
        // 4) mint liquidity providers LP tokens        
        _mint(to, liquidity);
        // 5) update mutable storage (reserves + cumulative oracle prices)
        _update(baseBalance, quoteBalance, _baseReserves, _quoteReserves);
        // 6) emit event since mutable storage was updated  
        emit Mint(msg.sender, baseAmount, quoteAmount);
    }

    error INSUFFICIENT_LIQUIDITY_BURNED();

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external nonReentrant returns (uint256 baseAmount, uint256 quoteAmount) {
        // 1) store any variables used more than once in memory to avoid SLOAD"s
        (uint112 _baseReserves, uint112 _quoteReserves,) = getReserves();   
        address _base = base;                                    
        address _quote = quote;                                    
        uint256 baseBalance = ERC20(_base).balanceOf(address(this));          
        uint256 quoteBalance = ERC20(_quote).balanceOf(address(this));          
        uint256 liquidity = balanceOf[address(this)];                 
        uint256 _totalSupply = totalSupply;         
        // 2) division was originally unchecked, using balances ensures pro-rata distribution
        baseAmount = uDiv(liquidity * baseBalance, _totalSupply); 
        quoteAmount = uDiv(liquidity * quoteBalance, _totalSupply);
        // 3) revert if amountOuts are both equal to zero
        if (baseAmount == 0 && quoteAmount == 0) revert INSUFFICIENT_LIQUIDITY_BURNED();
        // 4) burn LP tokens from this contract"s balance        
        _burn(address(this), liquidity);
        // 5) return liquidity providers underlying tokens        
        TransferHelper.safeTransfer(_base, to, baseAmount);
        TransferHelper.safeTransfer(_quote, to, quoteAmount);
        // 6) update mutable storage (reserves + cumulative oracle prices)        
        _update(ERC20(_base).balanceOf(address(this)), ERC20(_quote).balanceOf(address(this)), _baseReserves, _quoteReserves);
        // 7) emit event since mutable storage was updated     
        emit Burn(msg.sender, baseAmount, quoteAmount, to);
    }

    error INSUFFICIENT_OUTPUT_AMOUNT();
    error INSUFFICIENT_LIQUIDITY();
    error INSUFFICIENT_INPUT_AMOUNT();
    error INSUFFICIENT_INVARIANT();

    /// @notice Optimistically swap tokens, will revert if K is not satisfied
    /// @param baseAmountOut - amount of base tokens user wants to receive
    /// @param quoteAmountOut - amount of quote tokens user wants to receive
    /// @param to - recipient of 'output' tokens
    /// @param data - arbitrary data used during flashswaps
    function swap(
        uint256 baseAmountOut, 
        uint256 quoteAmountOut, 
        address to, 
        bytes calldata data
    ) external nonReentrant {
        // 1) revert if both amounts out are zero
        // 2) store reserves in memory to avoid SLOAD"s
        // 3) revert if both amounts out
        // 4) store any other variables used more than once in memory to avoid SLOAD"s
        if (baseAmountOut + quoteAmountOut == 0) revert INSUFFICIENT_OUTPUT_AMOUNT();
        (uint112 _baseReserves, uint112 _quoteReserves,) = getReserves();
        if (baseAmountOut > _baseReserves || quoteAmountOut >=_quoteReserves) revert INSUFFICIENT_LIQUIDITY();
        uint256 baseAmountIn;
        uint256 quoteAmountIn;
        uint256 baseBalance;
        uint256 quoteBalance;
        {
        address _base = base;
        address _quote = quote;
        // 1) optimistically transfer "to" base tokens
        // 2) optimistically transfer "to" quote tokens
        // 3) if data length is greater than 0, initiate flashswap
        // 4) store base token balance of contract in memory
        // 5) store quote token balance of contract in memory
        if (baseAmountOut > 0) TransferHelper.safeTransfer(_base, to, baseAmountOut); 
        if (quoteAmountOut > 0) TransferHelper.safeTransfer(_quote, to, quoteAmountOut);
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, baseAmountOut, quoteAmountOut, data);
        baseBalance = ERC20(_base).balanceOf(address(this));
        quoteBalance = ERC20(_quote).balanceOf(address(this));
        } 
        
        unchecked {
            // 1) calculate baseAmountIn by comparing contracts balance to last known reserve
            // 2) calculate quoteAmountIn by comparing contracts balance to last known reserve
            // 3) revert if user hasn't sent any tokens to the contract 
            if (baseBalance > _baseReserves - baseAmountOut) baseAmountIn = baseBalance - (_baseReserves - baseAmountOut);
            if (quoteBalance > _quoteReserves - quoteAmountOut) quoteAmountIn = quoteBalance - (_quoteReserves - quoteAmountOut);
            if (baseAmountIn + quoteAmountIn == 0) revert INSUFFICIENT_INPUT_AMOUNT();
        }

        {
        // 1) store swap fee in memory to save SLOAD
        // 2) revert if current k adjusted for fees is less than old k
        // 3) update mutable storage (reserves + cumulative oracle prices)
        // 4) emit event since mutable storage was updated
        uint256 _swapFee = swapFee; 
        uint256 baseBalanceAdjusted = baseBalance * BIPS_DIVISOR - baseAmountIn * _swapFee;
        uint256 quoteBalanceAdjusted = quoteBalance * BIPS_DIVISOR - quoteAmountIn * _swapFee;
        if (baseBalanceAdjusted * quoteBalanceAdjusted < uint(_baseReserves) * _quoteReserves * 1e8) revert INSUFFICIENT_INVARIANT();
        }
        _update(baseBalance, quoteBalance, _baseReserves, _quoteReserves);
        emit Swap(msg.sender, baseAmountIn, quoteAmountIn, baseAmountOut, quoteAmountOut, to);
    }

    // force balances to match reserves
    function skim(address to) external nonReentrant {
        // store any variables used more than once in memory to avoid SLOAD"s
        address _base = base;
        address _quote = quote;
        // transfer unaccounted reserves -> "to"
        TransferHelper.safeTransfer(_base, to, ERC20(_base).balanceOf(address(this)) - baseReserves);
        TransferHelper.safeTransfer(_quote, to, ERC20(_quote).balanceOf(address(this)) - quoteReserves);
    }

    // force reserves to match balances
    function sync() external nonReentrant {
        _update(
            ERC20(base).balanceOf(address(this)), 
            ERC20(quote).balanceOf(address(this)), 
            baseReserves, 
            quoteReserves
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              INTERNAL HELPERS                              */
    /* -------------------------------------------------------------------------- */

    // unchecked division
    function uDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {assembly {z := div(x, y)}}

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {z = x < y ? x : y;}
}

// naming left for old contract support
interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

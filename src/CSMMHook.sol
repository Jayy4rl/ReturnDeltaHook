// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

contract CSMMHook is BaseHook, IUnlockCallback {
    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;

        uint256 absAmount =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        BeforeSwapDelta resolvedDelta =
            toBeforeSwapDelta(-int128(params.amountSpecified), int128(params.amountSpecified));
        poolManager.mint(address(this), inputCurrency.toId(), absAmount);
        poolManager.burn(address(this), outputCurrency.toId(), absAmount);
        return (this.beforeSwap.selector, resolvedDelta, 0);
    }

    function addLiquidity(PoolKey calldata key, uint256 amount0, uint256 amount1) public {
        bytes memory data = abi.encode(key, amount0, amount1, msg.sender);
        poolManager.unlock(data);
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {

        require(msg.sender == address(poolManager), "only poolManager");
        (PoolKey memory key, uint256 amount0, uint256 amount1, address sender) =
            abi.decode(data, (PoolKey, uint256, uint256, address));
        if (amount0 > 0) {
            poolManager.sync(key.currency0);
            IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(sender, address(poolManager), amount0);
            poolManager.settle();
            poolManager.mint(address(this), key.currency0.toId(), amount0);
        }
        if (amount1 > 0) {
            poolManager.sync(key.currency1);
            IERC20Minimal(Currency.unwrap(key.currency1)).transferFrom(sender, address(poolManager), amount1);

            poolManager.settle();
            poolManager.mint(address(this), key.currency1.toId(), amount1);
        }
        return "";
    }
}

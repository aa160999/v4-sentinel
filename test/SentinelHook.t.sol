// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SentinelHook} from "../hooks/SentinelHook.sol";

contract SentinelHookTest is Test {
    using PoolIdLibrary for PoolKey;

    SentinelHook public hook;
    address public poolManager = address(0x1);
    address public keeper = address(0x2);
    address public unauthorizedUser = address(0x3);

    PoolKey public testPoolKey;

    function setUp() public {
        // 构建标准 Uniswap v4 PoolKey 测试结构体
        testPoolKey = PoolKey({
            currency0: Currency.wrap(address(0x10)),
            currency1: Currency.wrap(address(0x20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // 绑定满足 beforeSwap (0x0080) 权限前缀的模拟部署地址
        address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG));
        deployCodeTo("SentinelHook.sol:SentinelHook", abi.encode(poolManager, keeper), hookAddress);
        hook = SentinelHook(hookAddress);
    }

    /// @notice 验证非授权地址无法触发熔断
    function test_RevertWhen_UnauthorizedCallerSetsStatus() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(SentinelHook.UnauthorizedKeeper.selector);
        hook.setCircuitStatus(testPoolKey, true);
    }

    /// @notice 验证授权 Keeper (Circle Agent 钱包) 能够切换资金池熔断状态
    function test_KeeperCanToggleCircuitStatus() public {
        bytes32 poolId = testPoolKey.toId();

        // 触发熔断
        vm.prank(keeper);
        hook.setCircuitStatus(testPoolKey, true);
        assertTrue(hook.poolHalted(poolId));

        // 恢复交易
        vm.prank(keeper);
        hook.setCircuitStatus(testPoolKey, false);
        assertFalse(hook.poolHalted(poolId));
    }

    /// @notice 验证当处于熔断状态时，beforeSwap 拦截并阻断交易
    function test_BeforeSwapReverts_WhenPoolHalted() public {
        vm.prank(keeper);
        hook.setCircuitStatus(testPoolKey, true);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 100 ether,
            sqrtPriceLimitX96: 0
        });

        vm.expectRevert(SentinelHook.CircuitBreakerActive.selector);
        hook.beforeSwap(address(this), testPoolKey, params, "");
    }

    /// @notice 验证常规状态下 beforeSwap 正常放行
    function test_BeforeSwapPasses_WhenPoolNormal() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 100 ether,
            sqrtPriceLimitX96: 0
        });

        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = hook.beforeSwap(
            address(this),
            testPoolKey,
            params,
            ""
        );

        assertEq(selector, SentinelHook.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), BeforeSwapDelta.unwrap(BeforeSwapDeltaLibrary.ZERO_DELTA));
        assertEq(fee, 0);
    }

    /// @notice 验证 Keeper 权限的安全轮转机制
    function test_RotateKeeper() public {
        address newKeeper = address(0x4);

        vm.prank(keeper);
        hook.setKeeper(newKeeper);
        assertEq(hook.sentinelKeeper(), newKeeper);

        // 旧 Keeper 权限立即失效
        vm.prank(keeper);
        vm.expectRevert(SentinelHook.UnauthorizedKeeper.selector);
        hook.setCircuitStatus(testPoolKey, true);

        // 新 Keeper 接管状态修改权限
        vm.prank(newKeeper);
        hook.setCircuitStatus(testPoolKey, true);
        assertTrue(hook.poolHalted(testPoolKey.toId()));
    }
}

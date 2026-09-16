// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";

/// @title SentinelHook - Event-Driven Volatility Sentinel for Arc & Uniswap v4
/// @notice 配合链下异步哨兵与 Circle Agent 钱包执行亚秒级波动率风控与熔断
contract SentinelHook is BaseHook {
    // 触发熔断时的自定义错误
    error CircuitBreakerActive();
    error UnauthorizedKeeper();

    // 授权的守护智能体地址 (Circle Agent Wallet)
    address public sentinelKeeper;
    
    // 资金池熔断状态映射: poolId => isHalted
    mapping(bytes32 => bool) public poolHalted;

    // 风控状态变更事件
    event CircuitStatusUpdated(bytes32 indexed poolId, bool indexed isHalted, uint256 timestamp);
    event KeeperUpdated(address indexed oldKeeper, address indexed newKeeper);

    modifier onlyKeeper() {
        if (msg.sender != sentinelKeeper) revert UnauthorizedKeeper();
        _;
    }

    constructor(IPoolManager _poolManager, address _sentinelKeeper) BaseHook(_poolManager) {
        sentinelKeeper = _sentinelKeeper;
    }

    /// @notice 严格仅声明实际使用的 Hook 回调，降低 CREATE2 盐值计算难度
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,                 // 仅开启交易前波动率风控拦截
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice 交易前检查：由 Arc 亚秒级终局性保障的高频风控拦截
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external view override returns (bytes4, BeforeSwapDelta, uint24) {
        bytes32 poolId = key.toId();
        
        // 若链下 Python 哨兵已标记该池处于极端曲率状态，直接阻断交易
        if (poolHalted[poolId]) {
            revert CircuitBreakerActive();
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice 链下哨兵/Circle Agent 专属通道：毫秒级切换池熔断开关
    function setCircuitStatus(PoolKey calldata key, bool isHalted) external onlyKeeper {
        bytes32 poolId = key.toId();
        poolHalted[poolId] = isHalted;
        emit CircuitStatusUpdated(poolId, isHalted, block.timestamp);
    }

    /// @notice 变更 Keeper 地址（兼容多签或权限转移）
    function setKeeper(address _newKeeper) external onlyKeeper {
        emit KeeperUpdated(sentinelKeeper, _newKeeper);
        sentinelKeeper = _newKeeper;
    }
}

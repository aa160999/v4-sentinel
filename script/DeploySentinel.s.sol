// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SentinelHook} from "../hooks/SentinelHook.sol";

/// @notice Uniswap v4 Hook 权限掩码常量
/// beforeSwap 标志位定义为 1 << 7 = 0x0080
uint160 constant BEFORE_SWAP_FLAG = 1 << 7;

contract DeploySentinel is Script {
    function run() external {
        // 读取环境变量配置
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("V4_POOL_MANAGER_ADDRESS");
        address sentinelKeeper = vm.envAddress("CIRCLE_AGENT_WALLET_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        console2.log("Mining valid CREATE2 salt for SentinelHook on Arc Testnet...");
        console2.log("Required Hook Flag: beforeSwap (0x0080)");

        address deployer = vm.addr(deployerPrivateKey);
        bytes memory creationCode = type(SentinelHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManagerAddress), sentinelKeeper);
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);

        // 盐值碰撞：寻找满足 beforeSwap 标志位的目标地址
        uint256 salt = 0;
        address predictedAddress;
        
        while (true) {
            predictedAddress = computeCreate2Address(bytes32(salt), keccak256(bytecode), deployer);
            
            // 校验地址前缀标志位是否精确匹配 BEFORE_SWAP_FLAG (0x0080)
            if (uint160(predictedAddress) & Hooks.ALL_HOOK_MASK == BEFORE_SWAP_FLAG) {
                console2.log("Valid Salt Found:", salt);
                console2.log("Predicted Hook Address:", predictedAddress);
                break;
            }
            unchecked {
                ++salt;
            }
        }

        // 使用计算出的 Salt 通过 CREATE2 部署智能合约
        SentinelHook hook = new SentinelHook{salt: bytes32(salt)}(
            IPoolManager(poolManagerAddress),
            sentinelKeeper
        );

        require(address(hook) == predictedAddress, "Deployment address mismatch");
        console2.log("SentinelHook successfully deployed at:", address(hook));

        vm.stopBroadcast();
    }

    /// @dev 计算 CREATE2 部署地址
    function computeCreate2Address(
        bytes32 salt,
        bytes32 bytecodeHash,
        address deployer
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            deployer,
                            salt,
                            bytecodeHash
                        )
                    )
                )
            )
        );
    }
}

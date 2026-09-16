# ================================================================
# v4-Sentinel: Arc L1 & Uniswap v4 Automation Pipeline
# ================================================================

-include .env

.PHONY: all help install build test test-hook deploy-arc run-sentinel clean

all: build

help:
	@echo "v4-Sentinel Build & Execution Targets:"
	@echo "  make install       - 安装 Foundry 依赖与 Python 异步运行时环境"
	@echo "  make build         - 编译 Uniswap v4 Hook 与合约套件"
	@echo "  make test          - 执行全量 Foundry 单元测试"
	@echo "  make test-hook     - 仅执行 SentinelHook 熔断测试套件"
	@echo "  make deploy-arc    - 运行 CREATE2 盐值计算并部署至 Arc 测试网"
	@echo "  make run-sentinel  - 启动链下异步二阶导波动率监控哨兵"
	@echo "  make clean         - 清理编译缓存与构建产物"

install:
	@echo "==> 安装 Solidity 合约依赖库..."
	forge install foundry-rs/forge-std --no-commit
	forge install uniswap/v4-core --no-commit
	forge install uniswap/v4-periphery --no-commit
	@echo "==> 安装 Python 核心异步依赖..."
	pip install -r requirements.txt

build:
	@echo "==> 编译 Smart Contracts..."
	forge build

test:
	@echo "==> 执行全量单元测试与状态断言..."
	forge test -vvv

test-hook:
	@echo "==> 执行 SentinelHook 专属熔断逻辑测试..."
	forge test --match-contract SentinelHookTest -vvv

deploy-arc:
	@echo "==> 碰撞 Hook 地址前缀并部署至 Arc Public Testnet..."
	@if [ -z "$(ARC_RPC_URL)" ]; then echo "错误: 请先在 .env 中配置 ARC_RPC_URL"; exit 1; fi
	forge script script/DeploySentinel.s.sol:DeploySentinel \
		--rpc-url $(ARC_RPC_URL) \
		--broadcast \
		-vvvv

run-sentinel:
	@echo "==> 启动 v4-Sentinel 异步监控与智能体调度引擎..."
	python3 engine/surveillance.py

clean:
	@echo "==> 清理构建缓存..."
	forge clean
	rm -rf cache out

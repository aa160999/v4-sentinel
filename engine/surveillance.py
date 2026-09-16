import asyncio
import logging
import os
from collections import deque
from typing import Deque, List, Optional
import httpx
from web3 import AsyncWeb3
from web3.middleware import async_geth_poa_middleware

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] (SentinelEngine) %(message)s"
)
logger = logging.getLogger("v4-Sentinel")

# Minimal ABI for SentinelHook state mutation
SENTINEL_HOOK_ABI = [
    {
        "inputs": [
            {
                "components": [
                    {"internalType": "address", "name": "currency0", "type": "address"},
                    {"internalType": "address", "name": "currency1", "type": "address"},
                    {"internalType": "uint24", "name": "fee", "type": "uint24"},
                    {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
                    {"internalType": "address", "name": "hooks", "type": "address"}
                ],
                "internalType": "struct PoolKey",
                "name": "key",
                "type": "tuple"
            },
            {"internalType": "bool", "name": "isHalted", "type": "bool"}
        ],
        "name": "setCircuitStatus",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
]

class VolatilitySentinel:
    """
    Asynchronous Volatility Surveillance & Agentic Dispatch Engine for Arc & Uniswap v4.
    """
    def __init__(
        self,
        pool_key: tuple,
        hook_address: str,
        curvature_threshold: float = 0.05,
        window_size: int = 10,
        arc_rpc_url: Optional[str] = None
    ):
        self.pool_key = pool_key
        self.hook_address = AsyncWeb3.to_checksum_address(hook_address)
        self.threshold = curvature_threshold
        self.price_history: Deque[float] = deque(maxlen=window_size)
        self.is_active = True
        
        # Connect to Arc Public Testnet
        rpc = arc_rpc_url or os.getenv("ARC_RPC_URL", "https://testnet.arc.network")
        self.w3 = AsyncWeb3(AsyncWeb3.AsyncHTTPProvider(rpc))
        self.w3.middleware_onion.inject(async_geth_poa_middleware, layer=0)
        
        self.hook_contract = self.w3.eth.contract(
            address=self.hook_address,
            abi=SENTINEL_HOOK_ABI
        )
        
        # Circle Developer Wallet Credentials
        self.circle_api_key = os.getenv("CIRCLE_API_KEY", "")
        self.circle_wallet_id = os.getenv("CIRCLE_AGENT_WALLET_ID", "")
        self.circle_base_url = "https://api.circle.com/v1/w3s"

    def calculate_curvature(self) -> float:
        """
        Calculates discrete 2nd derivative (finite difference) of price sequence.
        Curvature = (P[t] - P[t-1]) - (P[t-1] - P[t-2]) = P[t] - 2*P[t-1] + P[t-2]
        """
        if len(self.price_history) < 3:
            return 0.0
        p = list(self.price_history)
        return p[-1] - (2 * p[-2]) + p[-3]

    def to_18_decimals(self, usdc_amount_6_dec: float) -> int:
        """
        Dual-Decimals Engine: Bridges standard 6-dec USDC to Arc 18-dec protocol gas representation.
        """
        return int(usdc_amount_6_dec * (10 ** 18))

    async def fetch_onchain_price(self) -> float:
        """
        Pulls latest state directly from Arc L1 RPC.
        Sub-second finality allows direct block queries without latency drag.
        """
        # In production, replace with slot/tick extraction from Uniswap v4 PoolManager
        await asyncio.sleep(0.2)
        import time
        return 1.0 + ((time.time() % 5) * 0.02)

    async def trigger_circuit_breaker(self, curvature: float, halt: bool):
        """
        Dispatches state-altering transaction onto Arc via Circle Developer-Controlled Wallet.
        """
        logger.warning(f"Extreme curvature {curvature:.4f} detected. Triggering Circuit Breaker (halt={halt}).")
        
        # Encode call data for setCircuitStatus
        call_data = self.hook_contract.encode_abi(
            "setCircuitStatus",
            args=[self.pool_key, halt]
        )

        if not self.circle_api_key or not self.circle_wallet_id:
            logger.info(f"[Simulation] Calldata generated for Hook {self.hook_address}: {call_data[:34]}...")
            return

        headers = {
            "Authorization": f"Bearer {self.circle_api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "walletId": self.circle_wallet_id,
            "contractAddress": self.hook_address,
            "abiFunctionSignature": "setCircuitStatus((address,address,uint24,int24,address),bool)",
            "abiParameters": [list(self.pool_key), halt],
            "fee": {
                "type": "level",
                "config": {"feeLevel": "HIGH"} # Native USDC gas
            }
        }

        async with httpx.AsyncClient(timeout=5.0) as client:
            try:
                response = await client.post(
                    f"{self.circle_base_url}/developer/transactions/contractExecution",
                    json=payload,
                    headers=headers
                )
                res_data = response.json()
                logger.info(f"Arc Execution Dispatched via Circle Agent Wallet: {res_data}")
            except Exception as e:
                logger.error(f"Failed to dispatch transaction via Circle Wallet: {str(e)}")

    async def monitor_loop(self):
        logger.info(f"Surveillance active for Hook: {self.hook_address} on Arc Network.")
        
        circuit_tripped = False
        while self.is_active:
            try:
                current_price = await self.fetch_onchain_price()
                self.price_history.append(current_price)

                if len(self.price_history) >= 3:
                    curvature = self.calculate_curvature()

                    if abs(curvature) > self.threshold and not circuit_tripped:
                        circuit_tripped = True
                        await self.trigger_circuit_breaker(curvature, halt=True)
                    elif abs(curvature) <= (self.threshold * 0.5) and circuit_tripped:
                        # Hysteresis reset: restore trading when volatility subsides
                        circuit_tripped = False
                        logger.info(f"Volatility stabilized ({curvature:.4f}). Resuming pool.")
                        await self.trigger_circuit_breaker(curvature, halt=False)

            except Exception as e:
                logger.error(f"Error in telemetry loop: {str(e)}")
                await asyncio.sleep(1.0)

async def main():
    # Sample Uniswap v4 PoolKey: (currency0, currency1, fee, tickSpacing, hooks)
    mock_pool_key = (
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        3000,
        60,
        "0x0000000000000000000000000000000000000080"
    )
    sentinel = VolatilitySentinel(
        pool_key=mock_pool_key,
        hook_address="0x0000000000000000000000000000000000000080",
        curvature_threshold=0.04
    )
    await sentinel.monitor_loop()

if __name__ == "__main__":
    asyncio.run(main())

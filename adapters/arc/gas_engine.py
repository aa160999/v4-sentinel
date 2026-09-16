"""
Arc L1 Dual-Decimals Precision Abstraction Engine
Handles mathematical conversion between standard ERC-20 USDC (6 decimals)
and Arc native gas protocol layer representation (18 decimals).
"""

from decimal import Decimal, ROUND_DOWN
from typing import Union

class DualDecimalsGasEngine:
    """
    Precision adapter for Arc network.
    - Asset Layer: USDC/EURC standard is 6 decimals.
    - Protocol Layer: Native gas calculations and RPC gas prices use 18 decimals.
    """
    ASSET_DECIMALS: int = 6
    GAS_DECIMALS: int = 18
    PRECISION_FACTOR: int = 10 ** (GAS_DECIMALS - ASSET_DECIMALS)  # 10^12

    @classmethod
    def usdc_to_native_gas_units(cls, amount_usdc: Union[float, str, Decimal]) -> int:
        """
        Converts human-readable or 6-decimal USDC value into 18-decimal native gas integer (wei-equivalent).
        Uses exact integer math to eliminate floating-point truncation risk.
        """
        dec_amount = Decimal(str(amount_usdc))
        # Scale to 18 decimals directly
        native_units = int((dec_amount * Decimal(10 ** cls.GAS_DECIMALS)).to_integral_value(rounding=ROUND_DOWN))
        return native_units

    @classmethod
    def native_gas_units_to_usdc(cls, native_units: int) -> Decimal:
        """
        Converts 18-decimal native gas units into standard 6-decimal USDC Decimal.
        """
        raw_scaled = Decimal(native_units) / Decimal(10 ** cls.GAS_DECIMALS)
        return raw_scaled.quantize(Decimal("0.000001"), rounding=ROUND_DOWN)

    @classmethod
    def calculate_max_fee_with_buffer(
        cls, 
        gas_limit: int, 
        gas_price_native_18: int, 
        buffer_multiplier: float = 1.15
    ) -> int:
        """
        Calculates maximum gas budget denominated in 18-decimal native gas units,
        applying a safety multiplier for volatile network congestion.
        """
        nominal_fee = gas_limit * gas_price_native_18
        buffered_fee = int(nominal_fee * buffer_multiplier)
        return buffered_fee

    @classmethod
    def has_sufficient_gas_allowance(
        cls, 
        native_balance_18: int, 
        required_fee_18: int
    ) -> bool:
        """
        Verifies if an agent wallet has sufficient native stablecoin gas balance
        prior to executing a Hook circuit mutation or transaction batch.
        """
        return native_balance_18 >= required_fee_18

import uuid
from typing import Dict, Any
from domain.order import Order
from application.ports.order_repository import OrderRepository


class CreateOrderUseCase:
    """Use case for creating orders"""

    def __init__(self, order_repository: OrderRepository):
        self._order_repository = order_repository

    async def execute(self, input_data: Dict[str, Any]) -> Order:
        """Execute order creation"""
        user_id = input_data.get("user_id")
        product = input_data.get("product")
        amount = input_data.get("amount")

        order_id = str(uuid.uuid4())
        order = Order(order_id, user_id, product, amount)

        await self._order_repository.create(order)
        return order

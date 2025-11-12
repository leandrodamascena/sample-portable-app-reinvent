from typing import Dict, List, Optional
from domain.order import Order
from application.ports.order_repository import OrderRepository


class InMemoryOrderRepository(OrderRepository):
    """In-memory implementation of OrderRepository"""

    def __init__(self):
        self._orders: Dict[str, Order] = {}

    async def create(self, order: Order) -> None:
        """Create a new order"""
        self._orders[order.id] = order

    async def find_by_id(self, id: str) -> Optional[Order]:
        """Find order by ID"""
        return self._orders.get(id)

    async def find_all(self) -> List[Order]:
        """Get all orders"""
        return list(self._orders.values())

    async def delete(self, id: str) -> None:
        """Delete order by ID"""
        if id not in self._orders:
            raise ValueError("Order not found")
        del self._orders[id]

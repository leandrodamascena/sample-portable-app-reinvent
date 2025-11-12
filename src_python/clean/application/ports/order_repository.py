from abc import ABC, abstractmethod
from typing import List, Optional
from domain.order import Order


class OrderRepository(ABC):
    """Interface for order persistence operations"""

    @abstractmethod
    async def create(self, order: Order) -> None:
        """Create a new order"""
        pass

    @abstractmethod
    async def find_by_id(self, id: str) -> Optional[Order]:
        """Find order by ID"""
        pass

    @abstractmethod
    async def find_all(self) -> List[Order]:
        """Get all orders"""
        pass

    @abstractmethod
    async def delete(self, id: str) -> None:
        """Delete order by ID"""
        pass

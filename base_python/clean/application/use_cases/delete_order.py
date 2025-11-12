from application.ports.order_repository import OrderRepository


class DeleteOrderUseCase:
    """Use case for deleting orders"""

    def __init__(self, order_repository: OrderRepository):
        self._order_repository = order_repository

    async def execute(self, id: str) -> None:
        """Execute order deletion"""
        order = await self._order_repository.find_by_id(id)

        if not order:
            raise ValueError("Order not found")

        await self._order_repository.delete(id)

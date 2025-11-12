from fastapi import FastAPI, HTTPException
from typing import Optional
from application.use_cases.create_user import CreateUserUseCase
from application.use_cases.delete_user import DeleteUserUseCase
from application.use_cases.create_order import CreateOrderUseCase
from application.use_cases.delete_order import DeleteOrderUseCase
from infrastructure.repositories.in_memory_user_repository import (
    InMemoryUserRepository,
)
from infrastructure.repositories.in_memory_order_repository import (
    InMemoryOrderRepository,
)
from application.ports.user_repository import UserRepository
from application.ports.order_repository import OrderRepository


def create_fastapi_app(
    custom_user_repository: Optional[UserRepository] = None,
    custom_order_repository: Optional[OrderRepository] = None,
) -> FastAPI:
    """FastAPI application factory"""

    app = FastAPI(title="Clean Architecture API")

    # Initialize repositories
    user_repository = custom_user_repository or InMemoryUserRepository()
    order_repository = custom_order_repository or InMemoryOrderRepository()

    # Initialize use cases
    create_user_use_case = CreateUserUseCase(user_repository)
    delete_user_use_case = DeleteUserUseCase(user_repository)
    create_order_use_case = CreateOrderUseCase(order_repository)
    delete_order_use_case = DeleteOrderUseCase(order_repository)

    # Health check
    @app.get("/health")
    def health_check():
        return {"message": "health from clean architecture"}

    # User endpoints
    @app.post("/users", status_code=201)
    async def create_user(data: dict):
        try:
            user = await create_user_use_case.execute(data)
            return user.to_dict()
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))

    @app.get("/users/{user_id}")
    async def get_user(user_id: str):
        user = await user_repository.find_by_id(user_id)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        return user.to_dict()

    @app.get("/users")
    async def get_users():
        users = await user_repository.find_all()
        return [user.to_dict() for user in users]

    @app.delete("/users/{user_id}", status_code=204)
    async def delete_user(user_id: str):
        try:
            await delete_user_use_case.execute(user_id)
        except ValueError as e:
            raise HTTPException(status_code=404, detail=str(e))

    # Order endpoints
    @app.post("/orders", status_code=201)
    async def create_order(data: dict):
        try:
            order = await create_order_use_case.execute(data)
            return order.to_dict()
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))

    @app.get("/orders/{order_id}")
    async def get_order(order_id: str):
        order = await order_repository.find_by_id(order_id)
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        return order.to_dict()

    @app.get("/orders")
    async def get_orders():
        orders = await order_repository.find_all()
        return [order.to_dict() for order in orders]

    @app.delete("/orders/{order_id}", status_code=204)
    async def delete_order(order_id: str):
        try:
            await delete_order_use_case.execute(order_id)
        except ValueError as e:
            raise HTTPException(status_code=404, detail=str(e))

    return app

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
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
import os


def create_fastapi_app(
    custom_user_repository: Optional[UserRepository] = None,
    custom_order_repository: Optional[OrderRepository] = None,
) -> FastAPI:
    """FastAPI application factory"""

    app = FastAPI(title="Clean Architecture API")

    # Setup templates
    templates_dir = os.path.join(os.path.dirname(__file__), "templates")
    print(f"🔍 Looking for templates in: {templates_dir}")
    print(f"📁 Templates directory exists: {os.path.exists(templates_dir)}")
    if os.path.exists(templates_dir):
        print(f"📄 Files in templates: {os.listdir(templates_dir)}")
    
    try:
        templates = Jinja2Templates(directory=templates_dir)
    except Exception as e:
        print(f"❌ Error loading templates: {e}")
        templates = None

    # Initialize repositories
    user_repository = custom_user_repository or InMemoryUserRepository()
    order_repository = custom_order_repository or InMemoryOrderRepository()

    # Initialize use cases
    create_user_use_case = CreateUserUseCase(user_repository)
    delete_user_use_case = DeleteUserUseCase(user_repository)
    create_order_use_case = CreateOrderUseCase(order_repository)
    delete_order_use_case = DeleteOrderUseCase(order_repository)

    # Health check - Web UI
    @app.get("/health", response_class=HTMLResponse)
    async def health_check_page(request: Request):
        if templates is None:
            return {"status": "healthy", "message": "health from clean architecture"}
        return templates.TemplateResponse(
            "health.html",
            {"request": request, "status": "healthy"}
        )
    
    # Health check - API
    @app.get("/api/health")
    def health_check_api():
        return {"status": "healthy", "message": "health from clean architecture"}

    # User endpoints - Web UI
    @app.get("/users", response_class=HTMLResponse)
    async def get_users_page(request: Request):
        if templates is None:
            raise HTTPException(
                status_code=500, 
                detail=f"Templates not loaded. Directory: {templates_dir}"
            )
        users = await user_repository.find_all()
        return templates.TemplateResponse(
            "users.html",
            {"request": request, "users": users}
        )

    # User endpoints - API
    @app.post("/api/users", status_code=201)
    async def create_user(data: dict):
        try:
            user = await create_user_use_case.execute(data)
            return user.to_dict()
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))

    @app.get("/api/users/{user_id}")
    async def get_user(user_id: str):
        user = await user_repository.find_by_id(user_id)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        return user.to_dict()

    @app.get("/api/users")
    async def get_users_api():
        users = await user_repository.find_all()
        return [user.to_dict() for user in users]

    @app.delete("/api/users/{user_id}", status_code=204)
    async def delete_user(user_id: str):
        try:
            await delete_user_use_case.execute(user_id)
        except ValueError as e:
            raise HTTPException(status_code=404, detail=str(e))

    # Order endpoints - Web UI
    @app.get("/orders", response_class=HTMLResponse)
    async def get_orders_page(request: Request):
        if templates is None:
            raise HTTPException(
                status_code=500, 
                detail=f"Templates not loaded. Directory: {templates_dir}"
            )
        orders = await order_repository.find_all()
        return templates.TemplateResponse(
            "orders.html",
            {"request": request, "orders": orders}
        )

    # Order endpoints - API
    @app.post("/api/orders", status_code=201)
    async def create_order(data: dict):
        try:
            order = await create_order_use_case.execute(data)
            return order.to_dict()
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))

    @app.get("/api/orders/{order_id}")
    async def get_order(order_id: str):
        order = await order_repository.find_by_id(order_id)
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        return order.to_dict()

    @app.get("/api/orders")
    async def get_orders_api():
        orders = await order_repository.find_all()
        return [order.to_dict() for order in orders]

    @app.delete("/api/orders/{order_id}", status_code=204)
    async def delete_order(order_id: str):
        try:
            await delete_order_use_case.execute(order_id)
        except ValueError as e:
            raise HTTPException(status_code=404, detail=str(e))

    return app

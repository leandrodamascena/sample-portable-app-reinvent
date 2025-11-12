import uvicorn
from infrastructure.http.fastapi_app import create_fastapi_app


def run_server():
    """Run the FastAPI server"""
    print("🚀 Starting Clean Architecture Server...")
    print("📡 Server running at http://localhost:8080")
    print("\n📍 Available endpoints:")
    print("  GET    /health         - Health check")
    print("  POST   /users          - Create user")
    print("  GET    /users          - Get all users")
    print("  GET    /users/{id}     - Get user")
    print("  DELETE /users/{id}     - Delete user")
    print("  POST   /orders         - Create order")
    print("  GET    /orders         - Get all orders")
    print("  GET    /orders/{id}    - Get order")
    print("  DELETE /orders/{id}    - Delete order")
    print()

    app = create_fastapi_app()
    uvicorn.run(app, host="0.0.0.0", port=9000)


if __name__ == "__main__":
    run_server()

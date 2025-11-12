import uvicorn
from app import app

if __name__ == "__main__":
    print("🚀 Starting Monolith Server...")
    print("📡 Server running at http://localhost:8080")
    print("\n📍 Available endpoints:")
    print("  GET    /health       - Health check")
    print("  POST   /users        - Create user")
    print("  GET    /users/{id}   - Get user")
    print("  POST   /orders       - Create order")
    print("  GET    /orders/{id}  - Get order")
    print()

    uvicorn.run(app, host="0.0.0.0", port=9000)

from fastapi import FastAPI
from users import save_user, get_user
from orders import save_order, get_order

app = FastAPI()


# Health check
@app.get("/health")
def health_check():
    return {"message": "health from monolith"}


# User endpoints
@app.post("/users", status_code=201)
def create_user(data: dict):
    return save_user(data)


@app.get("/users/{user_id}")
def retrieve_user(user_id: str):
    return get_user(user_id)


# Order endpoints
@app.post("/orders", status_code=201)
def create_order(data: dict):
    return save_order(data)


@app.get("/orders/{order_id}")
def retrieve_order(order_id: str):
    return get_order(order_id)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)

"""
AWS Lambda handler for the Clean Architecture FastAPI application
"""
from mangum import Mangum
from infrastructure.http.fastapi_app import create_fastapi_app

# Create the FastAPI app
app = create_fastapi_app()

# Create the Lambda handler using Mangum
handler = Mangum(app, lifespan="off")
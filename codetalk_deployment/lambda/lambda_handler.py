import json
from mangum import Mangum
from infrastructure.http.fastapi_app import create_fastapi_app

# Create FastAPI app
app = create_fastapi_app()

# Create Mangum handler for AWS Lambda
mangum_handler = Mangum(app, lifespan="off")

def handler(event, context):
    """
    AWS Lambda handler function
    """
    return mangum_handler(event, context)
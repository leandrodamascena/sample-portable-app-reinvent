import logging
from datetime import datetime
from flask import Flask, request, jsonify
from .controllers.user_controller import UserController
from .services.user_service import UserService
from .repositories.user_repository import InMemoryUserRepository

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_app() -> Flask:
    """Create and configure Flask application"""
    app = Flask(__name__)
    
    # Development mode indicator
    logger.info('🛠️  Development mode enabled')
    
    @app.before_request
    def log_request():
        """Logging middleware"""
        timestamp = datetime.now().isoformat()
        logger.info(f'[{timestamp}] {request.method} {request.path}')
        logger.info(f'Request headers: {dict(request.headers)}')
        
        if request.is_json and request.get_json():
            logger.info(f'Request body: {request.get_json()}')
    
    @app.route('/health', methods=['GET'])
    def health_check():
        """Health check endpoint"""
        logger.info('Health check requested')
        status = 'healthy'
        logger.info(f'Health check responded with status: {status}')
        return jsonify({'status': status})
    
    @app.route('/version', methods=['GET'])
    def version_check():
        """Version endpoint"""
        logger.info('Version check requested')
        version = 'layered-architecture'
        logger.info(f'Version check responded with: {version}')
        return jsonify({'version': version})
    
    # Initialize dependencies
    user_repository = InMemoryUserRepository()
    user_service = UserService(user_repository)
    user_controller = UserController(user_service)
    
    # Setup routes
    @app.route('/users', methods=['POST'])
    def create_user():
        return user_controller.create_user()
    
    @app.route('/users', methods=['GET'])
    def list_users():
        return user_controller.list_users()
    
    @app.route('/users/<user_id>', methods=['GET'])
    def get_user(user_id: str):
        return user_controller.get_user(user_id)
    
    @app.route('/users/<user_id>', methods=['DELETE'])
    def delete_user(user_id: str):
        return user_controller.delete_user(user_id)
    
    # Export dependencies for testing
    app.user_repository = user_repository
    app.user_service = user_service
    app.user_controller = user_controller
    
    return app

if __name__ == '__main__':
    app = create_app()
    app.run(debug=True)

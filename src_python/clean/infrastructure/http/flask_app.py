import asyncio
import logging
from datetime import datetime
from flask import Flask, request, jsonify, Response
from typing import Optional, Tuple, Union
from application.use_cases.create_user import CreateUserInput
from application.use_cases.create_user import CreateUserUseCase
from application.use_cases.delete_user import DeleteUserUseCase
from infrastructure.repositories.in_memory_user_repository import InMemoryUserRepository
from application.ports.user_repository import UserRepository



logger = logging.getLogger(__name__)

def create_flask_app(custom_user_repository: Optional[UserRepository] = None) -> Flask:
    """Flask application factory that can be used in any environment"""
    
    app = Flask(__name__)
    
    @app.before_request
    def log_request():
        """Logging middleware"""
        timestamp = datetime.now().isoformat()
        logger.info(f'[{timestamp}] {request.method} {request.url}')
        logger.debug(f'Request headers: {dict(request.headers)}')
        
        if request.is_json and request.get_json():
            logger.debug(f'Request body: {request.get_json()}')
    
    # Initialize dependencies
    logger.info('Initializing Flask application dependencies')
    user_repository = custom_user_repository or InMemoryUserRepository()
    create_user_use_case = CreateUserUseCase(user_repository)
    delete_user_use_case = DeleteUserUseCase(user_repository)
    
    @app.route('/health', methods=['GET'])
    def health_check() -> Tuple[Response, int]:
        """Health check endpoint (useful for container environments)"""
        logger.debug('Health check requested')
        response = jsonify({'status': 'healthy'})
        logger.info('Health check responded with status: healthy')
        return response, 200
    
    @app.route('/version', methods=['GET'])
    def version_check() -> Tuple[Response, int]:
        """Version endpoint"""
        logger.debug('Version check requested')
        version = 'clean-architecture'
        logger.info(f'Version check responded with: {version}')
        return jsonify({'version': version}), 200
    
    @app.route('/users', methods=['POST'])
    def create_user() -> Tuple[Response, int]:
        """Create user endpoint"""
        try:
            logger.info('Creating new user')
            data = request.get_json()
            
            if not data:
                return jsonify({'error': 'Request body is required'}), 400
            
            user = asyncio.run(create_user_use_case.execute(data))
            logger.info(f'User created successfully: {user.id}')
            return jsonify(user.to_dict()), 201
            
        except ValueError as error:
            error_msg = str(error)
            logger.error(f'Error creating user: {error_msg}')
            return jsonify({'error': error_msg}), 400
        except Exception as error:
            error_msg = str(error) if isinstance(error, Exception) else 'Unknown error'
            logger.error(f'Error creating user: {error_msg}')
            return jsonify({'error': error_msg}), 500
    
    @app.route('/users', methods=['GET'])
    def get_users() -> Tuple[Response, int]:
        """Get all users endpoint"""
        logger.info('Retrieving all users')
        users = asyncio.run(user_repository.find_all())
        logger.info(f'Retrieved users count: {len(users)}')
        return jsonify([user.to_dict() for user in users]), 200
    
    @app.route('/users/<user_id>', methods=['GET'])
    def get_user(user_id: str) -> Tuple[Response, int]:
        """Get user by ID endpoint"""
        logger.info(f'Retrieving user by id: {user_id}')
        user = asyncio.run(user_repository.find_by_id(user_id))
        
        if not user:
            logger.warning(f'User not found: {user_id}')
            return jsonify({'error': 'User not found'}), 404
        
        logger.info(f'User found: {user.id}')
        return jsonify(user.to_dict()), 200
    
    @app.route('/users/<user_id>', methods=['DELETE'])
    def delete_user(user_id: str) -> Tuple[Union[str, Response], int]:
        """Delete user endpoint"""
        try:
            asyncio.run(delete_user_use_case.execute(user_id))
            return '', 204
            
        except ValueError as error:
            if str(error) == 'User not found':
                logger.warning(f'User not found when attempting to delete: {user_id}')
                return jsonify({'error': 'User not found'}), 404
            else:
                logger.error(f'Error deleting user: {str(error)}')
                return jsonify({'error': str(error)}), 500
        except Exception as error:
            error_msg = str(error) if isinstance(error, Exception) else 'Unknown error'
            logger.error(f'Error deleting user: {error_msg}')
            return jsonify({'error': error_msg}), 500
    
    return app

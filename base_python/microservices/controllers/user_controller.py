import asyncio
import logging
from flask import request, jsonify, Response
from typing import Tuple, Union
from ..services.user_service import UserService

logger = logging.getLogger(__name__)

class UserController:
    """Controller layer for user operations"""
    
    def __init__(self, user_service: UserService):
        self._user_service = user_service
    
    def create_user(self) -> Tuple[Response, int]:
        """Create a new user endpoint"""
        try:
            data = request.get_json()
            if not data:
                return jsonify({'error': 'Request body is required'}), 400
            
            # Run async function in sync context
            user = asyncio.run(self._user_service.create_user(data))
            return jsonify(user.to_dict()), 201
            
        except ValueError as e:
            # Handle validation errors (400)
            message = str(e)
            if any(keyword in message.lower() for keyword in ['must be', 'invalid', 'required']):
                status_code = 400
            else:
                status_code = 500
            
            return jsonify({'error': message}), status_code
            
        except Exception as e:
            logger.error(f'Unexpected error creating user: {str(e)}')
            return jsonify({'error': 'Unknown error'}), 500
    
    def get_user(self, user_id: str) -> Tuple[Response, int]:
        """Get user by ID endpoint"""
        try:
            user = asyncio.run(self._user_service.get_user(user_id))
            return jsonify(user.to_dict()), 200
            
        except ValueError as e:
            return jsonify({'error': str(e)}), 404
        except Exception as e:
            logger.error(f'Unexpected error getting user: {str(e)}')
            return jsonify({'error': 'Unknown error'}), 500
    
    def list_users(self) -> Tuple[Response, int]:
        """List all users endpoint"""
        try:
            users = asyncio.run(self._user_service.list_users())
            return jsonify([user.to_dict() for user in users]), 200
            
        except Exception as e:
            logger.error(f'Unexpected error listing users: {str(e)}')
            return jsonify({'error': 'Unknown error'}), 500
    
    def delete_user(self, user_id: str) -> Tuple[Union[str, Response], int]:
        """Delete user by ID endpoint"""
        try:
            asyncio.run(self._user_service.delete_user(user_id))
            return '', 204
            
        except ValueError as e:
            return jsonify({'error': str(e)}), 404
        except Exception as e:
            logger.error(f'Unexpected error deleting user: {str(e)}')
            return jsonify({'error': 'Unknown error'}), 500

import os
import logging
from .app import create_app

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main():
    """Main server entry point"""
    logger.info('Starting local development server...')
    logger.info('Creating Flask application instance')
    logger.info('Initializing Flask application dependencies')
    
    app = create_app()
    
    port = int(os.environ.get('PORT', 8080))
    logger.info(f'Using port: {port}')
    
    print("""
 _                               _ 
| |    __ _ _   _  ___ _ __ ___  __| |
| |   / _` | | | |/ _ \ '__/ _ \/ _` |
| |__| (_| | |_| |  __/ | |  __/ (_| |
|_____\__,_|\__, |\___|_|  \___|\__,_|
            |___/                    
""")
    
    logger.info('🚀 Server successfully started!')
    logger.info(f'📡 Server running at http://localhost:{port}\n')
    logger.info('📍 Available endpoints:')
    logger.info('  GET    /health    - Health check endpoint')
    logger.info('  GET    /version   - Get architecture version')
    logger.info('  POST   /users     - Create a new user')
    logger.info('  GET    /users     - List all users')
    logger.info('  GET    /users/:id - Get user by ID')
    logger.info('  DELETE /users/:id - Delete user by ID')
    
    try:
        app.run(host='0.0.0.0', port=port, debug=True)
    except OSError as e:
        if 'Address already in use' in str(e):
            logger.error(f'❌ Port {port} is already in use')
            logger.error('Please try using a different port by setting the PORT environment variable')
            exit(1)
        else:
            logger.error(f'❌ Server error: {e}')
            exit(1)

if __name__ == '__main__':
    main()

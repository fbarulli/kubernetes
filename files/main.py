import logging
import os
import traceback
from typing import List
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr, validator
from sqlalchemy.engine import create_engine
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy import text

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# creating a FastAPI server
server = FastAPI(title='User API')

# creating a connection to the database
mysql_url = os.getenv('MYSQL_URL', 'localhost')
mysql_user = os.getenv('MYSQL_USER', 'root')
mysql_password = os.getenv('MYSQL_PASSWORD')
database_name = os.getenv('MYSQL_DATABASE', 'Main')

if not mysql_password:
    logger.error("MySQL password not provided in environment variables")
    raise ValueError("MySQL password is required")

# recreating the URL connection with explicit TCP port
connection_url = f'mysql://{mysql_user}:{mysql_password}@{mysql_url}:3306/{database_name}'
logger.info(f"Connecting to MySQL at {mysql_url}:3306")

try:
    # creating the connection
    mysql_engine = create_engine(connection_url)
    logger.info("Successfully created database engine")
except Exception as e:
    logger.error(f"Failed to create database engine: {str(e)}")
    logger.error(traceback.format_exc())
    raise

# creating a User class
class User(BaseModel):
    user_id: int
    username: str
    email: EmailStr

    @validator('username')
    def username_must_not_be_empty(cls, v):
        if not v.strip():
            raise ValueError('username cannot be empty')
        return v.strip()

    @validator('user_id')
    def user_id_must_be_positive(cls, v):
        if v < 0:
            raise ValueError('user_id must be positive')
        return v

@server.get('/status')
async def get_status():
    """Returns 1 to indicate the service is running"""
    logger.info("Health check endpoint called")
    return {"status": 1}

@server.get('/users', response_model=List[User])
async def get_users():
    """Retrieve all users from the database"""
    try:
        with mysql_engine.connect() as connection:
            results = connection.execute(text('SELECT * FROM Users;'))
            users = [
                User(
                    user_id=row[0],
                    username=row[1],
                    email=row[2]
                ) for row in results.fetchall()
            ]
            logger.info(f"Successfully retrieved {len(users)} users")
            return users
    except SQLAlchemyError as e:
        error_msg = f"Database error when fetching users: {str(e)}\nType: {type(e)}\nArgs: {e.args}"
        logger.error(error_msg)
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Database error occurred")
    except Exception as e:
        logger.error(f"Unexpected error when fetching users: {str(e)}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Internal server error")

@server.get('/users/{user_id}', response_model=User)
async def get_user(user_id: int):
    """Retrieve a specific user by ID
    
    Args:
        user_id (int): The ID of the user to retrieve
    
    Raises:
        HTTPException: If user is not found (404) or database error occurs (500)
    """
    try:
        with mysql_engine.connect() as connection:
            # Use parameterized query to prevent SQL injection
            results = connection.execute(
                'SELECT * FROM Users WHERE Users.id = %s', (user_id,)
            )
            user_data = results.fetchone()
            
            if not user_data:
                logger.warning(f"User with ID {user_id} not found")
                raise HTTPException(
                    status_code=404,
                    detail='Unknown User ID'
                )
            
            user = User(
                user_id=user_data[0],
                username=user_data[1],
                email=user_data[2]
            )
            logger.info(f"Successfully retrieved user {user_id}")
            return user
            
    except SQLAlchemyError as e:
        logger.error(f"Database error when fetching user {user_id}: {str(e)}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Database error occurred")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error when fetching user {user_id}: {str(e)}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Internal server error")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(server, host="0.0.0.0", port=8000)
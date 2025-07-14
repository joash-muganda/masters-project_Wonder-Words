import os
from flask import jsonify, request
from functools import wraps
import json
from datetime import datetime, timedelta
import jwt
from db.db import db, ChildAccount

# Secret key for JWT
SECRET_KEY = os.environ.get('JWT_SECRET_KEY', 'dev_secret_key')

def save_child_account(username, pin, parent_uid, display_name, age):
    """
    Save a child account to the database
    """
    try:
        child_account = ChildAccount(
            username=username,
            pin=pin,
            parent_uid=parent_uid,
            display_name=display_name,
            age=age
        )
        db.session.add(child_account)
        db.session.commit()
        return True
    except Exception as e:
        db.session.rollback()
        print(f"Error saving child account: {e}")
        return False

def verify_child_credentials(username, pin):
    """
    Verify child login credentials
    """
    child_account = ChildAccount.query.filter_by(username=username, pin=pin).first()
    if child_account:
        return {
            'pin': child_account.pin,
            'parent_uid': child_account.parent_uid,
            'display_name': child_account.display_name,
            'age': child_account.age
        }
    return None

def generate_child_token(username, parent_uid, display_name, age):
    """
    Generate a JWT token for a child account
    """
    payload = {
        'username': username,
        'parent_uid': parent_uid,
        'display_name': display_name,
        'age': age,
        'is_child': True,
        'exp': datetime.utcnow() + timedelta(days=1)  # Token expires in 1 day
    }
    return jwt.encode(payload, SECRET_KEY, algorithm='HS256')

def verify_child_token(token):
    """
    Verify a child JWT token
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=['HS256'])
        if 'is_child' in payload and payload['is_child']:
            return payload
        return None
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None

def child_auth_required(f):
    """
    Decorator to require child authentication for a route
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Get the authorization header
        auth_header = request.headers.get('Authorization')
        
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'No valid authorization token provided'}), 401
        
        # Extract the token
        token = auth_header.split('Bearer ')[1]
        
        # Verify the token
        child_data = verify_child_token(token)
        
        if not child_data:
            return jsonify({'error': 'Invalid or expired token'}), 401
        
        # Add the child data to the request context
        request.child_user = child_data
        
        return f(*args, **kwargs)
    
    return decorated_function

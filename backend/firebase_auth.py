import os
import requests
from functools import wraps
from flask import request, jsonify

# Firebase project ID
FIREBASE_PROJECT_ID = 'wonder-words-bac10'

def verify_firebase_token(id_token):
    """
    Verify the Firebase ID token using the Firebase Auth REST API
    """
    try:
        # Use Firebase Auth REST API to verify the token
        url = f'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={os.environ.get("FIREBASE_API_KEY")}'
        payload = {'idToken': id_token}
        response = requests.post(url, json=payload)
        
        if response.status_code == 200:
            user_data = response.json()
            if 'users' in user_data and len(user_data['users']) > 0:
                return user_data['users'][0]
        
        return None
    except Exception as e:
        print(f"Error verifying Firebase token: {e}")
        return None

def firebase_auth_required(f):
    """
    Decorator to require Firebase authentication for a route
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Get the authorization header
        auth_header = request.headers.get('Authorization')
        
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'No valid authorization token provided'}), 401
        
        # Extract the token
        id_token = auth_header.split('Bearer ')[1]
        
        # Verify the token
        user = verify_firebase_token(id_token)
        
        if not user:
            return jsonify({'error': 'Invalid or expired token'}), 401
        
        # Add the user to the request context
        request.firebase_user = user
        
        return f(*args, **kwargs)
    
    return decorated_function

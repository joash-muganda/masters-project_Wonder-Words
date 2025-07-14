import os
import requests
import json
from flask import Flask
from db.db import db, init_db, ChildAccount
from child_auth import save_child_account
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Create a Flask app
app = Flask(__name__)

# Initialize the database
init_db(app)

def get_firebase_users():
    """
    Get all users from Firebase
    """
    try:
        # Use Firebase Auth REST API to get all users
        url = f'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={os.environ.get("FIREBASE_API_KEY")}'
        
        # We need to provide a valid ID token to get all users
        # First, get an ID token by signing in with the admin account
        admin_email = os.environ.get("ADMIN_EMAIL")
        admin_password = os.environ.get("ADMIN_PASSWORD")
        
        if not admin_email or not admin_password:
            print("Admin email and password are required")
            return []
        
        # Sign in with admin account
        sign_in_url = f'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={os.environ.get("FIREBASE_API_KEY")}'
        sign_in_payload = {
            'email': admin_email,
            'password': admin_password,
            'returnSecureToken': True
        }
        sign_in_response = requests.post(sign_in_url, json=sign_in_payload)
        
        if sign_in_response.status_code != 200:
            print(f"Failed to sign in with admin account: {sign_in_response.text}")
            return []
        
        id_token = sign_in_response.json().get('idToken')
        
        # Now use the ID token to get all users
        payload = {'idToken': id_token}
        response = requests.post(url, json=payload)
        
        if response.status_code == 200:
            user_data = response.json()
            if 'users' in user_data:
                return user_data['users']
        
        return []
    except Exception as e:
        print(f"Error getting Firebase users: {e}")
        return []

def sync_child_accounts():
    """
    Sync child accounts from Firebase to the backend database
    """
    with app.app_context():
        # Get all users from Firebase
        firebase_users = get_firebase_users()
        
        # Filter for child accounts
        child_accounts = []
        for user in firebase_users:
            # Check if the user is a child account
            # Child accounts have a custom claim 'accountType' set to 'child'
            if user.get('customClaims', {}).get('accountType') == 'child':
                child_accounts.append(user)
        
        print(f"Found {len(child_accounts)} child accounts in Firebase")
        
        # For each child account, check if it exists in the backend database
        for child in child_accounts:
            # Get the child's username from the custom claims
            username = child.get('customClaims', {}).get('username')
            
            if not username:
                print(f"Child account {child.get('localId')} has no username")
                continue
            
            # Check if the child account exists in the backend database
            existing_account = ChildAccount.query.filter_by(username=username).first()
            
            if existing_account:
                print(f"Child account {username} already exists in the backend database")
                continue
            
            # Get the child's details from the custom claims
            pin = child.get('customClaims', {}).get('pin')
            display_name = child.get('displayName')
            age = child.get('customClaims', {}).get('age')
            parent_uid = child.get('customClaims', {}).get('parentUid')
            
            if not all([pin, display_name, age, parent_uid]):
                print(f"Child account {username} is missing required fields")
                continue
            
            # Save the child account to the backend database
            success = save_child_account(username, pin, parent_uid, display_name, age)
            
            if success:
                print(f"Child account {username} synced to the backend database")
            else:
                print(f"Failed to sync child account {username} to the backend database")

if __name__ == '__main__':
    sync_child_accounts()

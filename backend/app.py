from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
from db.db import db
from pydub import AudioSegment
import io
import base64

# Clear only the 'story_assignment' table from the metadata
from db.db import db, init_db, Conversation, Message, SenderType, ChildAccount, StoryAssignment, StoryTheme
from llm.llm import handler, meta_prompt_generator, new_story_generator, add_to_story
from firebase_auth import firebase_auth_required
from child_auth import (
    save_child_account, verify_child_credentials, generate_child_token,
    child_auth_required
)
import os
from dotenv import load_dotenv
import random
import ast
import heapq

# Load environment variables
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Initialize the SQLAlchemy db instance
init_db(app)

@app.route('/log_message', methods=['POST'])
def log_message(conversation_id, sender_type, code, content):
    # Process the data as needed
    # For example, you can log it or save it to a database

    try:
        print(
            f"Logging message with conversation_id: {conversation_id}, sender_type: {sender_type}, code: {code}, content: {content}")
        message = Message(
            conversation_id=conversation_id,
            sender_type=sender_type,
            code=code,
            content=content
        )
        db.session.add(message)
        db.session.commit()
        print(f"Message logged: {message}")
    except Exception as e:
        print(f"Error logging message: {e}")
    return jsonify({'status': 'success', 'message': 'Log message received'}), 200


@app.route('/fetch_conversations_by_user', methods=['POST'])
def fetch_conversations_by_user(user_id):
    conversations = Conversation.query.filter_by(user_id=user_id).all()
    return conversations


@app.route('/fetch_messages_by_user_and_conversation', methods=['POST'])
def fetch_messages_by_user_and_conversation(user_id, conversation_id):
    messages = Message.query.join(Conversation).filter(
        Conversation.user_id == user_id,
        Message.conversation_id == conversation_id
    ).order_by(Message.created_at).all()
    return messages

@app.route('/generate_meta_prompt', methods=['POST'])
def generate_meta_prompt():
    data = request.get_json()
    user_input = data.get('user_input')
    if user_input:
        try:
            # Call the meta_prompt_generator function with the user input
            meta_prompt, meta_features, meta_vocabulary = meta_prompt_generator(user_input)
            return jsonify({"response": meta_prompt, 'meta_features': meta_features, 'meta_vocabulary': meta_vocabulary})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    else:
        return jsonify({"error": "User input is required"}), 400

def generate_new_story(query):
    try:
        story = new_story_generator(query)
    except ValueError:
        return jsonify({"message": "Invalid response from new_story_generator"})
    return story


def add_to_existing_story(conversation_id, query):
    try:
        extended_story = add_to_story(conversation_id, query)
    except ValueError:
        return jsonify({"message": "Invalid response from add_to_story"})
    return extended_story


@app.route('/handle_request', methods=['POST'])
@firebase_auth_required
def handle_request():
    data = request.get_json()
    query = data.get('query')
    # Use Firebase user ID from the token
    user_id = request.firebase_user.get('localId', 'user_id_placeholder')
    conversation_id = data.get('conversation_id')
    if query:
        print(f"Received query: {query}")
        try:
            code = int(handler(query))
            print(f"Handler returned code: {code}")
        except ValueError:
            return jsonify({"message": "Invalid response from handler"})
        
        if code == 2 and not conversation_id:  # If the user asks for a new story and there is not existing conversation
            return jsonify({"confirmation": "Are you sure you want to start a new story? Please respond with 'yes' or 'no'.", "conversation_id": conversation_id})
        if code == 2 and conversation_id:  # If the user asks for a new story and there is an existing conversation
            code = 3 # set the code to 3 to add to the existing story

        if conversation_id:
            conversation = Conversation.query.get(conversation_id)
            if not conversation:
                return jsonify({"message": "Invalid conversation ID"})
        else:
            conversation = Conversation(user_id=user_id)
            db.session.add(conversation)
            db.session.commit()
            conversation_id = conversation.id

        print(
            f"Calling log_message with conversation_id: {conversation.id}, sender_type: {SenderType.USER}, code: {code}, query: {query}")
        log_message(conversation.id, SenderType.USER, code, query)
        ### the following is never reached if the code is 2 and is handled in CONFIRM_NEW_STORY_ROUTE ###
        if code == 0:  # If the user asks for something unrelated to telling a story
            response = "Sorry, I can only tell stories. Please ask me to tell you a story."
        elif code == 1:  # If the user asks for something related to a story but violates safety rules
            response = "Sorry, I can't tell that story. Please ask me to tell you a story."
        elif code == 2:  # If the user asks for a new story
            story_data = generate_new_story(query)
            if isinstance(story_data, dict):
                title = story_data.get("title", "New Story")
                story = story_data.get("story", "")
                # Format the response with title and story
                response = f"TITLE: {title}\n\n STORY, PART #1: {story}"
                log_message(conversation.id, SenderType.MODEL, code, response)
            else:
                response = story_data.replace('STORY:', 'STORY, PART #1:')
                log_message(conversation.id, SenderType.MODEL, code, response)
        elif code == 3:  # If the user asks for an addition to an existing story
            story_data = add_to_existing_story(conversation.id, query)
            if isinstance(story_data, dict):
                title = story_data.get("title", "Continued Story")
                story = story_data.get("story", "")
                part = story_data.get("part", 1)
                # Format the response with title and story
                response = f"TITLE: {title}\n\n STORY, PART #{part}: {story}"
                log_message(conversation.id, SenderType.MODEL, code, response)
            else:
                print('continued story data:', story_data)
                response = story_data
                log_message(conversation.id, SenderType.MODEL, code, response)
        else:
            response = f"Invalid code: {code}"

        return jsonify({"response": response, "conversation_id": conversation_id})
    else:
        return jsonify({"message": "Query required"})


@app.route('/confirm_new_story', methods=['POST'])
@firebase_auth_required
def confirm_new_story_route():
    data = request.get_json()
    query = data.get('query')
    # Use Firebase user ID from the token
    user_id = request.firebase_user.get('localId', 'user_id_placeholder')
    confirmation = data.get('confirmation')
    conversation_id = data.get('conversation_id')

    if query and confirmation:
        if confirmation.lower() == 'y':
            conversation = Conversation(user_id=user_id)
            db.session.add(conversation)
            db.session.commit()
            # logging the user message
            log_message(conversation.id, SenderType.USER, 2, query)

            story_data = generate_new_story(query)
            if isinstance(story_data, dict):
                title = story_data.get("title", "New Story")
                story = story_data.get("story", "")
                # Format the response with title and story
                response = f"TITLE: {title}\n\n STORY, PART #1: {story}"
                log_message(conversation.id, SenderType.MODEL, 2, response)
            else:
                response = story_data.replace('STORY:', 'STORY, PART #1:')
                log_message(conversation.id, SenderType.MODEL, 2, response)

            return jsonify({"message": "New story initiated.", "response": response, "conversation_id": conversation.id})
        elif confirmation.lower() == 'n':
            return jsonify({"message": "New story request canceled."})
        else:
            return jsonify({"message": "Invalid confirmation. Please confirm by sending 'y' or 'n'."})
    else:
        return jsonify({"message": "Query and confirmation required"})


@app.route('/delete_conversation', methods=['DELETE'])
@firebase_auth_required
def delete_conversation():
    # Use Firebase user ID from the token
    user_id = request.firebase_user.get('localId', 'user_id_placeholder')
    conversation_id = request.args.get('conversation_id')

    if not conversation_id:
        return jsonify({"error": "Conversation ID is required"}), 400

    try:
        # Verify the conversation belongs to the user
        conversation = Conversation.query.filter_by(
            id=conversation_id, user_id=user_id).first()
        if not conversation:
            return jsonify({"error": "Conversation not found or access denied"}), 404

        # Delete any story assignments associated with this conversation
        StoryAssignment.query.filter_by(
            conversation_id=conversation_id).delete()

        # Delete all messages associated with this conversation
        Message.query.filter_by(conversation_id=conversation_id).delete()

        # Delete the conversation
        db.session.delete(conversation)
        db.session.commit()

        return jsonify({"message": "Conversation deleted successfully"})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500


@app.route('/get_conversations', methods=['GET'])
@firebase_auth_required
def get_conversations():
    # Use Firebase user ID from the token
    user_id = request.firebase_user.get('localId', 'user_id_placeholder')

    # Get pagination parameters from the query string
    page = request.args.get('page')  # Optional
    limit = request.args.get('limit')  # Optional

    try:
        # Fetch conversations for the user
        conversations_query = Conversation.query.filter_by(user_id=user_id)

        if page is not None and limit is not None:
            # Apply pagination if both page and limit are provided
            page = int(page)
            limit = int(limit)
            conversations = conversations_query.order_by(Conversation.created_at.desc()) \
                .offset(page * limit).limit(limit).all()
        else:
            # Fetch all conversations if pagination is not provided
            conversations = conversations_query.order_by(Conversation.created_at.desc()).all()

        result = []
        for conversation in conversations:
            # Get the first message (story) for each conversation
            messages = Message.query.filter_by(
                conversation_id=conversation.id).order_by(Message.created_at).all()
            first_story = next(
                (msg for msg in messages if msg.sender_type == SenderType.MODEL), None)

            result.append({
                'id': conversation.id,
                'created_at': conversation.created_at.isoformat(),
                'preview': first_story.content[:100] + '...' if first_story else 'No story content',
                'message_count': len(messages)
            })

        # Include pagination metadata only if pagination is applied
        if page is not None and limit is not None:
            return jsonify({
                "conversations": result,
                "total_conversations": conversations_query.count(),
                "page": page,
                "limit": limit
            })
        else:
            # Return all conversations without pagination metadata
            return jsonify({
                "conversations": result
            })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/get_conversation_messages', methods=['GET'])
@firebase_auth_required
def get_conversation_messages():
    # Use Firebase user ID from the token
    user_id = request.firebase_user.get('localId', 'user_id_placeholder')
    conversation_id = request.args.get('conversation_id')

    if not conversation_id:
        return jsonify({"error": "Conversation ID is required"}), 400

    try:
        # Verify the conversation belongs to the user
        conversation = Conversation.query.filter_by(
            id=conversation_id, user_id=user_id).first()
        if not conversation:
            return jsonify({"error": "Conversation not found or access denied"}), 404

        messages = fetch_messages_by_user_and_conversation(
            user_id, conversation_id)
        result = []

        for message in messages:
            result.append({
                'id': message.id,
                'sender_type': message.sender_type.name,
                'content': message.content,
                'created_at': message.created_at.isoformat(),
                'code': message.code
            })

        return jsonify({"messages": result})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/create_child_account', methods=['POST'])
def create_child_account():
    data = request.get_json()
    username = data.get('username')
    pin = data.get('pin')
    display_name = data.get('display_name')
    age = data.get('age')
    data = request.get_json()
    parent_uid = data.get('parent_uid')  # Parent UID passed from the frontend
    print('parent_uid from frontend:', parent_uid)
    if not parent_uid:
        return jsonify({"error": "Parent UID is required"}), 400

    if not all([username, pin, display_name, age]):
        return jsonify({"error": "All fields are required"}), 400

    # Check if username already exists
    existing_account = ChildAccount.query.filter_by(username=username).first()
    if existing_account:
        return jsonify({"error": "Username already exists"}), 409

    # Save the child account
    success = save_child_account(username, pin, parent_uid, display_name, age)

    if success:
        return jsonify({"message": "Child account created successfully"})
    else:
        return jsonify({"error": "Failed to create child account"}), 500


@app.route('/child_login', methods=['POST'])
def child_login():
    data = request.get_json()
    username = data.get('username')
    pin = data.get('pin')

    if not all([username, pin]):
        return jsonify({"error": "Username and PIN are required"}), 400

    # Verify child credentials
    child_data = verify_child_credentials(username, pin)

    if not child_data:
        return jsonify({"error": "Invalid username or PIN"}), 401

    # Generate a token for the child
    token = generate_child_token(
        username,
        child_data['parent_uid'],
        child_data['display_name'],
        child_data['age']
    )

    return jsonify({
        "token": token,
        "display_name": child_data['display_name'],
        "age": child_data['age']
    })


@app.route('/get_child_accounts', methods=['POST'])
@firebase_auth_required
def get_child_accounts():
    data = request.get_json()
    parent_uid = data.get('parent_uid')  # Parent UID passed from the frontend
    # get the firebase user using the parent_uid
    parent = request.firebase_user.get(parent_uid)
    print(parent)

    # Print the parent_uid for debugging
    print(f"Parent UID: {parent_uid}")

    # Query all child accounts 
    child_accounts = ChildAccount.query.all()
    # Filter child accounts by parent UID
    child_accounts = [account for account in child_accounts if account.parent_uid == parent_uid]

    # Print the number of child accounts found
    print(f"Found {len(child_accounts)} child accounts (all)")

    # Format the results
    result = []
    for account in child_accounts:
        result.append({
            'username': account.username,
            'display_name': account.display_name,
            'age': account.age
        })

    return jsonify({"child_accounts": result})


@app.route('/handle_child_request', methods=['POST'])
@child_auth_required
def handle_child_request():
    data = request.get_json()
    query = data.get('query')
    conversation_id = data.get('conversation_id')

    # Use parent UID from the child token for database operations
    parent_uid = request.child_user.get('parent_uid', 'user_id_placeholder')

    if query:
        try:
            code = int(handler(query))
        except ValueError:
            return jsonify({"message": "Invalid response from handler"})

        if conversation_id:
            conversation = Conversation.query.get(conversation_id)
            if not conversation:
                return jsonify({"message": "Invalid conversation ID"})
        else:
            conversation = Conversation(user_id=parent_uid)
            db.session.add(conversation)
            db.session.commit()
            conversation_id = conversation.id

        if code == 2 and conversation_id:  # If the user asks for a new story and there is an existing conversation
            return jsonify({"confirmation": "Are you sure you want to start a new story? Please respond with 'yes' or 'no'.", "conversation_id": conversation_id})

        log_message(conversation.id, SenderType.USER, code, query)

        if code == 0:  # If the user asks for something unrelated to telling a story
            response = "Sorry, I can only tell stories. Please ask me to tell you a story."
        elif code == 1:  # If the user asks for something related to a story but violates safety rules
            response = "Sorry, I can't tell that story. Please ask me to tell you a story."
        elif code == 2:  # If the user asks for a new story
            story_data = generate_new_story(query)
            if isinstance(story_data, dict):
                title = story_data.get("title", "New Story")
                story = story_data.get("story", "")
                # Format the response with title and story
                response = f"TITLE: {title}\n\nSTORY: {story}"
                log_message(conversation.id, SenderType.MODEL, code, response)
            else:
                response = story_data
                log_message(conversation.id, SenderType.MODEL, code, response)
        elif code == 3:  # If the user asks for an addition to an existing story
            story_data = add_to_existing_story(conversation.id, query)
            title = story_data.get("title", "New Story")
            story = story_data.get("story", "")
            # Format the response with title and story
            response = f"TITLE: {title}\n\nSTORY: {story}"
            log_message(conversation.id, SenderType.MODEL, code, response)
        else:
            response = f"Invalid code: {code}"

        return jsonify({"response": response, "conversation_id": conversation_id})
    else:
        return jsonify({"message": "Query required"})


@app.route('/confirm_child_new_story', methods=['POST'])
@child_auth_required
def confirm_child_new_story():
    data = request.get_json()
    query = data.get('query')
    confirmation = data.get('confirmation')
    conversation_id = data.get('conversation_id')

    # Use parent UID from the child token for database operations
    parent_uid = request.child_user.get('parent_uid', 'user_id_placeholder')

    if query and confirmation:
        if confirmation.lower() == 'y':
            conversation = Conversation(user_id=parent_uid)
            db.session.add(conversation)
            db.session.commit()

            story_data = generate_new_story(query)
            if isinstance(story_data, dict):
                title = story_data.get("title", "New Story")
                story = story_data.get("story", "")
                # Format the response with title and story
                response = f"TITLE: {title}\n\nSTORY: {story}"
                log_message(conversation.id, SenderType.MODEL, 2, response)
            else:
                response = story_data
                log_message(conversation.id, SenderType.MODEL, 2, response)

            return jsonify({"message": "New story initiated.", "response": response, "conversation_id": conversation.id})
        elif confirmation.lower() == 'n':
            return jsonify({"message": "New story request canceled."})
        else:
            return jsonify({"message": "Invalid confirmation. Please confirm by sending 'y' or 'n'."})
    else:
        return jsonify({"message": "Query and confirmation required"})


@app.route('/get_child_conversations', methods=['GET'])
@child_auth_required
def get_child_conversations():
    # accepts parent_uid and assigned stories parameters
    # Use parent UID from the child token for database operations
    parent_uid = request.child_user.get('parent_uid', 'user_id_placeholder')
    # Get pagination parameters from the query string
    page = request.args.get('page')  # Optional
    limit = request.args.get('limit')  # Optional
    assigned_stories = request.args.get('assigned_stories')  # Optional
    # convert string encoded list of strings to python list of strings
    if assigned_stories:
        assigned_stories = ast.literal_eval(assigned_stories)
    # if the args are strings it means they are not passed (type 'null' in dart -> None in python)
    if type(page) == str:
        page = None
    if type(limit) == str:
        limit = None
    if type(assigned_stories) != list:
        assigned_stories = None
    if (type(assigned_stories) != None) & (len(assigned_stories) == 0):
        print('returning none')
        return jsonify({
            "conversations": [],
            "total_conversations": 0,
            "page": page,
            "limit": limit
        })
    try:
    
        # Fetch conversations for the parent
        conversations_query = Conversation.query.filter_by(user_id=parent_uid)
        total_conversations = conversations_query.count()
        # Filter conversations based on assigned stories if provided
        if assigned_stories:
            # Fetch only conversations with assigned stories
            #app.logger.info(f"Assigned stories: {assigned_stories}")
            assigned_stories = [int(story_id) for story_id in assigned_stories]
            #app.logger.info(f"Assigned stories: {assigned_stories}")
            conversations_query = conversations_query.filter(
                Conversation.id.in_(assigned_stories)
            )
            # log message to flask
            #app.logger.info(f"Conversations query: {conversations_query}")
        if page is not None and limit is not None and len(assigned_stories) > limit:
            # Apply pagination if both page and limit are provided & lots of assigned stories
            page = int(page)
            limit = int(limit)
            
            # if limit is greather than the total_conversations, set it to total_conversations
            if limit >= total_conversations:
                limit = total_conversations
            print(f"Page: {page}, Limit: {limit}")
            print(f"Total conversations: {total_conversations}")
            # Check if all conversations have already been returned
            if page * limit > total_conversations:
                return jsonify({
                    "conversations": [],
                    "total_conversations": total_conversations,
                    "page": page,
                    "limit": limit
                })
            conversations = conversations_query.order_by(Conversation.created_at.desc()) \
                .offset(page * limit).limit(limit).all()
        else:
            # Fetch all conversations if pagination is not provided
            conversations = conversations_query.order_by(Conversation.created_at.desc()).all()

        result = []
        for conversation in conversations:
            # Get the first message (story) for each conversation
            messages = Message.query.filter_by(
                conversation_id=conversation.id).order_by(Message.created_at).all()
            first_story = next(
                (msg for msg in messages if msg.sender_type == SenderType.MODEL), None)

            result.append({
                'id': conversation.id,
                'created_at': conversation.created_at.isoformat(),
                'preview': first_story.content[:100] + '...' if first_story else 'No story content',
                'message_count': len(messages)
            })

        # Include pagination metadata only if pagination is applied
        if page is not None and limit is not None:
            return jsonify({
                "conversations": result,
                "total_conversations": conversations_query.count(),
                "page": page,
                "limit": limit
            })
        else:
            # Return all conversations without pagination metadata
            return jsonify({
                "conversations": result
            })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/get_child_conversation_messages', methods=['GET'])
@child_auth_required
def get_child_conversation_messages():
    # Use parent UID from the child token for database operations
    parent_uid = request.child_user.get('parent_uid', 'user_id_placeholder')
    conversation_id = request.args.get('conversation_id')

    if not conversation_id:
        return jsonify({"error": "Conversation ID is required"}), 400

    try:
        # Verify the conversation belongs to the parent
        conversation = Conversation.query.filter_by(
            id=conversation_id, user_id=parent_uid).first()
        if not conversation:
            return jsonify({"error": "Conversation not found or access denied"}), 404

        messages = fetch_messages_by_user_and_conversation(
            parent_uid, conversation_id)
        result = []

        for message in messages:
            result.append({
                'id': message.id,
                'sender_type': message.sender_type.name,
                'content': message.content,
                'created_at': message.created_at.isoformat(),
                'code': message.code
            })

        return jsonify({"messages": result})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/assign_story', methods=['POST'])
@firebase_auth_required
def assign_story():
    data = request.get_json()
    conversation_id = data.get('conversation_id')
    child_username = data.get('child_username')
    title = data.get('title')

    print(f"Assigning story with conversation_id: {conversation_id}, child_username: {child_username}, title: {title}")
    if not all([conversation_id, child_username, title]):
        return jsonify({"error": "All fields are required"}), 400

    # Retrieve the parent UID from the Firebase token
    parent_uid = request.firebase_user.get('localId')

    # Verify the conversation exists and belongs to the parent
    conversation = Conversation.query.filter_by(
        id=conversation_id, user_id=parent_uid).first()
    if not conversation:
        return jsonify({"error": "Conversation not found or access denied"}), 404
    print(f"Conversation found: {conversation}")

    # Verify the child account exists and belongs to the parent
    child_account = ChildAccount.query.filter_by(
        username=child_username, parent_uid=parent_uid).first()
    print(f"Child account found: {child_account}")
    if not child_account:
        return jsonify({"error": "Child account not found or access denied"}), 404

    # Create the story assignment
    assignment = StoryAssignment(
        conversation_id=conversation_id,
        child_username=child_username,
        title=title
    )

    db.session.add(assignment)
    db.session.commit()

    return jsonify({"message": "Story assigned successfully", "assignment_id": assignment.id})


@app.route('/get_assigned_stories', methods=['GET'])
@child_auth_required
def get_assigned_stories():
    # Get the child username from the token
    username = request.child_user.get('username')

    # Query assigned stories for this child
    assignments = StoryAssignment.query.filter_by(
        child_username=username).all()

    result = []
    for assignment in assignments:
        # Get the first model message from the conversation (the story content)
        first_story = Message.query.filter_by(
            conversation_id=assignment.conversation_id,
            sender_type=SenderType.MODEL
        ).order_by(Message.created_at).first()

        if first_story:
            result.append({
                'id': assignment.id,
                'conversation_id': assignment.conversation_id,
                'title': assignment.title,
                'assigned_at': assignment.assigned_at.isoformat(),
                'preview': first_story.content[:100] + '...' if len(first_story.content) > 100 else first_story.content
            })

    return jsonify({"assigned_stories": result})


@app.route('/generate_themed_story', methods=['POST'])
@child_auth_required
def generate_themed_story():
    data = request.get_json()
    theme = data.get('theme')

    if not theme:
        return jsonify({"error": "Theme is required"}), 400

    # Validate the theme
    try:
        story_theme = StoryTheme(theme)
    except ValueError:
        return jsonify({"error": "Invalid theme"}), 400

    # Generate a prompt based on the theme
    prompts = {
        StoryTheme.DRAGONS: [
            "Tell me a story about a friendly dragon who helps a village",
            "Tell me a story about a dragon who can't breathe fire",
            "Tell me a story about a baby dragon learning to fly"
        ],
        StoryTheme.SPACE: [
            "Tell me a story about astronauts discovering a new planet",
            "Tell me a story about aliens visiting Earth",
            "Tell me a story about a space adventure with talking robots"
        ],
        StoryTheme.ANIMALS: [
            "Tell me a story about talking animals in a forest",
            "Tell me a story about a brave little mouse",
            "Tell me a story about animals working together to solve a problem"
        ],
        StoryTheme.MAGIC: [
            "Tell me a story about a child discovering they have magic powers",
            "Tell me a story about a magical school",
            "Tell me a story about a wizard's apprentice"
        ],
        StoryTheme.PIRATES: [
            "Tell me a story about a kind pirate who helps others",
            "Tell me a story about finding a treasure map",
            "Tell me a story about a pirate adventure with a talking parrot"
        ],
        StoryTheme.DINOSAURS: [
            "Tell me a story about friendly dinosaurs",
            "Tell me a story about a time-traveling adventure to see dinosaurs",
            "Tell me a story about a baby dinosaur finding its family"
        ],
        StoryTheme.FAIRY_TALE: [
            "Tell me a fairy tale about a brave princess who saves a prince",
            "Tell me a fairy tale with a happy ending",
            "Tell me a fairy tale about magical creatures in an enchanted forest"
        ],
        StoryTheme.ADVENTURE: [
            "Tell me an adventure story about exploring a mysterious cave",
            "Tell me an adventure story about finding a lost city",
            "Tell me an adventure story about a magical journey"
        ]
    }

    # Select a random prompt for the chosen theme
    prompt = random.choice(prompts[story_theme])

    # Use parent UID from the child token for database operations
    parent_uid = request.child_user.get('parent_uid', 'user_id_placeholder')

    # Create a new conversation
    conversation = Conversation(user_id=parent_uid)
    db.session.add(conversation)
    db.session.commit()

    # Log the user message
    log_message(conversation.id, SenderType.USER, 2, prompt)

    # Generate the story
    story_data = generate_new_story(prompt)
    if isinstance(story_data, dict):
        title = story_data.get("title", f"{story_theme.value.title()} Story")
        story = story_data.get("story", "")
        # Format the response with title and story
        response = f"TITLE: {title}\n\nSTORY: {story}"
        log_message(conversation.id, SenderType.MODEL, 2, response)
    else:
        response = story_data
        title = f"{story_theme.value.title()} Story"
        log_message(conversation.id, SenderType.MODEL, 2, response)

    return jsonify({
        "response": response,
        "conversation_id": conversation.id,
        "title": title,
        "theme": theme
    })

# heap data structure to store the audio files based on their filesize and the time they were created to delete the oldest & largest files first
class AudioHeap:
    def __init__(self):
        self.heap = []

    def push(self, file_path):
        file_size = os.path.getsize(file_path)
        created_at = os.path.getctime(file_path)
        heapq.heappush(self.heap, (file_size, created_at, file_path))

    def pop(self):
        return heapq.heappop(self.heap)[2]  # Return only the file path

    def remove(self, file_path):
        self.heap = [item for item in self.heap if item[2] != file_path]
        heapq.heapify(self.heap)

    # return size of the heap
    def size(self):
        return len(self.heap)
# Initialize the heap
audio_heap = AudioHeap()
# Set the maximum size of the heap
MAX_HEAP_SIZE = 10  # Maximum number of audio files to keep

# post method to recieve bytes of audio file from the frontend and save it to the server
@app.route('/upload_audio', methods=['POST'])
def upload_audio():
    request_data = request.get_json()
    # Get the audio file bytes and filename from the request
    audio_bytes = request_data.get('bytes')  # 'bytes' should match the key used in the frontend
    audio_filename = request_data.get('filename')
    if not audio_bytes:
        return jsonify({"error": "No audio file provided"}), 400
    if not audio_filename:
        return jsonify({"error": "No filename provided"}), 400
    
    # Ensure the 'uploads' directory exists
    upload_dir = 'uploads'
    save_path = os.path.join(upload_dir, audio_filename) + '.mp3'
    if not os.path.exists(upload_dir):
        os.makedirs(upload_dir)
    # base case check if the filename is in the heap
    if save_path in [item[2] for item in audio_heap.heap]:
        print(f"File {audio_filename} already cached. Returning existing file.")
        return jsonify({"message": "File already cached", "file_path": save_path}), 200

    # Decode the bytes (if they are base64-encoded)
    audio_data = base64.b64decode(audio_bytes)
    # Convert the bytes to an MP3 file
    try:
        audio = AudioSegment.from_file(io.BytesIO(audio_data), format="mp3")
        try:
            audio.export(save_path, format="mp3")
            # check if the size of the heap is greater than the max size
            if audio_heap.size() >= MAX_HEAP_SIZE:
                # remove the largest file from the heap
                largest_file = audio_heap.pop()
                os.remove(largest_file)
                print(f"Removed file {largest_file} from the server to make space for new files.")
            # add the new file to the heap
            audio_heap.push(save_path)
            print(f"File {audio_filename} saved to {save_path}")
        except Exception as e:
            print(f"Error exporting audio: {e}")
            return jsonify({"error": "Failed to save audio file"}), 500

    except Exception as e:
        return jsonify({"error": f"Failed to process audio file: {e}"}), 500

    return jsonify({"message": "Audio file uploaded successfully", "file_path": save_path}), 200

# get method to download the audio file from the server
@app.route('/download_audio', methods=['GET'])
def download_audio():
    file_path = request.args.get('file_path')
    print(f"Received file path: {file_path}")
    if not file_path:
        return jsonify({"error": "No file path provided"}), 400

    # Check if the file exists
    if not os.path.exists(file_path):
        return jsonify({"error": "File not found"}), 404

    # Send the mp3 back
    return send_file(file_path, as_attachment=True, mimetype='audio/mpeg')


if __name__ == '__main__':
    import sys
    import logging
    log = logging.getLogger('werkzeug')
    log.setLevel(logging.ERROR)
    logging.basicConfig(level=logging.INFO)
    app.run(host='0.0.0.0', port=5000, debug=True)

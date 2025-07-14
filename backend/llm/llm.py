import os
from dotenv import load_dotenv
from flask import jsonify
from openai import OpenAI
from db.db import db, Conversation, Message, SenderType
import mysql
from mysql.connector import Error
import pandas as pd
import re

model = "gpt-4o-mini"

load_dotenv(dotenv_path=os.path.join(
    os.path.dirname(__file__), '..', '..', '.env'))

client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY"),
)
# Database connection details
host = os.getenv("DB_HOST")
user = os.getenv("DB_USER")
password = os.getenv("DB_PASSWORD")
database = os.getenv("DB_NAME")

def connect_to_database():
    """Create a connection to the MySQL database."""
    try:
        connection = mysql.connector.connect(
            host=host,
            user=user,
            password=password,
            database=database
        )
        if connection.is_connected():
            print("Connected to the database")
            return connection
    except Error as e:
        print(f"Error while connecting to MySQL: {e}")
        return None

def add_to_prompt_table(features, vocabulary, user_prompt, model_response):
    """Add a new prompt and its features to the MySQL database."""
    connection = connect_to_database()
    if connection:
        print("Adding new prompt to the database...")
        try:
            cursor = connection.cursor()
            # Insert the new prompt into the prompts table
            insert_query = """
                INSERT INTO prompt_data (features, vocabulary, user_prompt, model_response)
                VALUES (%s, %s, %s, %s)
            """
            cursor.execute(insert_query, (features, vocabulary, user_prompt, model_response))
            connection.commit()
            print("New prompt added successfully")
        except Error as e:
            print(f"Error while inserting data: {e}")
        finally:
            cursor.close()
            connection.close()
    else:
        print("Failed to connect to the database. Prompt not added.")

def add_to_meta_prompt_table(user_meta_prompt, prompt_vocabulary, prompt_narratives, model_meta_response, model_meta_vocabulary, model_meta_narratives):
    """Add a new meta prompt and its response to the MySQL database."""
    connection = connect_to_database()
    if connection:
        try:
            cursor = connection.cursor()
            # Insert the new meta prompt into the meta_prompts table
            insert_query = """
                INSERT INTO meta_prompt_data (user_meta_prompt, prompt_vocabulary, prompt_narratives, model_meta_response, model_meta_vocabulary, model_meta_narratives)
                VALUES (%s, %s, %s, %s, %s, %s)
            """
            cursor.execute(insert_query, (user_meta_prompt, prompt_vocabulary, prompt_narratives, model_meta_response, model_meta_vocabulary, model_meta_narratives))
            connection.commit()
            print("New meta prompt added successfully")
        except Error as e:
            print(f"Error while inserting data: {e}")
        finally:
            cursor.close()
            connection.close()

# This subprompt is used to handle the language of the user's input.
language_handling_subprompt = "Important: Respond to the user's input in the language they are using. Interpret their request in their language to make decisions to your instructions."
valid_additions = ['What happens next?','Different Ending', 'Make it funny', 'Add a twist']
def handler(query):
    chat_completion = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": (
                    f"{language_handling_subprompt}"
                    "You are the handler for a storytelling AI that can generate children's stories based on a given prompt."
                    "You should take the user input and decide what to do with it by returning the appropriate code, which is the integer only. Ex. 0, 1, 2, 3, 4, 5."
                    "If the user asks for something unsafe or violent, respond with code 0."
                    "If the user asks for something related to a story but violates safety rules, respond with code 1."
                    "If the user asks for a new story, respond with code 2."
                    f"If the user asks for an addition to an existing story, for example {valid_additions},  respond with code 3."
                    "If the user asks about a detail in the story, consider it as a request for an addition to the story and respond with code 3."
                ),
            },
            {
                "role": "user",
                "content": query,
            }
        ],
        model=model,
    )
    return chat_completion.choices[0].message.content
feature_vocabulary_subprompt = (
    "\nImportant:"
    "The narrative features provide guidance on the plot and structure of the story, "
    "while the vocabulary words are specific terms that should ALWAYS be included in the story. "
)
def features_and_vocabulary(query):
    # chat completion to extract interesting vocabulary from the query
    vocabulary_completion = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": (
                    f"{language_handling_subprompt}"
                    "You are a vocabulary expert for a storytelling AI."
                    "You should create a list of some existing or novel (around 3-5) vocabulary words that pair well with the story query."
                    "Return the vocabulary as a comma-separated list of words."
                    "Aim to include words that are unique, descriptive, and engaging for children."
                    "Do not include common words or phrases, and only return the vocabulary words without any additional text."
                ),
            },
            {
                "role": "user",
                "content": query,
            }
        ],
        model=model,
    )
    # chat completion to generate narrative features from the query
    example_narrative_features = ['dialogue', 'twist', 'moralvalue', 'foreshadowing', 'goodending', 'badending', 'characterdevelopment']
    features_completion = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": (
                    f"{language_handling_subprompt}"
                    "You are a narrative features expert for a storytelling AI."
                    "You should create a list of some existing or novel (around 3-5) narrative features that pair well with the story query."
                    f"Example narrative features include: {', '.join(example_narrative_features)}."
                    "Return the features as a comma-separated list of words."
                    "Aim to include storytelling or literature narratives that are unique, descriptive, and engaging for children."
                    "Do not include common words or phrases, and only return the narrative features without any additional text."
                ),
            },
            {
                "role": "user",
                "content": query,
            }
        ],
        model=model,
    )

    vocabulary_response = vocabulary_completion.choices[0].message.content
    features_response = features_completion.choices[0].message.content
    return vocabulary_response, features_response


def story_prompt_generator(query):
    """Generate a story prompt based on the user's input."""
    # Fetch vocabulary and narrative features from the query
    vocabulary_response, features_response = features_and_vocabulary(query)
    formatted_prompt = (
        f"{feature_vocabulary_subprompt}"
        f"Relevant vocabulary: {vocabulary_response}\n"
        f"Relevant narrative features: {features_response}\n"
        f"User prompt: {query}\n"
    )

    return vocabulary_response, features_response, formatted_prompt

meta_prompt_system_prompt = (
                    f"{language_handling_subprompt}"
                    "You are a prompt evaluation expert for a storytelling AI."
                    "You should take the user input and edit their prompt for improvement."
                    "The updated prompt should be clear, concise, and engaging."
                    "The vocabulary and narrative should be unique, descriptive, and engaging for children."
                    "The goal is to improve the prompt, not to provide a story."
                    "You should only return the updated prompt in the following format:\n\n"
                    "Story Request: [The updated prompt content]\n\n"
                    "Vocabulary: [The updated vocabulary content as a list]\n\n"
                    "Narratives: [The updated narrative features content as a list]\n\n"
)

meta_prompt_gen_user_prompt = '''<|im_start|>user
                    {language_handling_subprompt} 
                    Below is a prompt evaluation request that describes a task, paired with an input that provides further context. Write a response that appropriately completes the request.
                    Do not include any additional information or context in your response. Only include the updated prompt, vocabulary, and narrative features.
                    

                    Prompt for Evaluation: 
                    {user_prompt}

                    <|im_end|>

                    <|im_start|>assistant
                    Prompt:'''

def meta_prompt_generator(user_prompt):
    """Generate a meta prompt based on the user's input."""
    # Fetch vocabulary and narrative and formatted prompt from the query
    vocabulary, features, formatted_prompt = story_prompt_generator(user_prompt)
    # chat completion to generate a meta prompt
    chat_completion = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": meta_prompt_system_prompt,
            },
            {
                "role": "user",
                "content": meta_prompt_gen_user_prompt.format(
                    language_handling_subprompt=language_handling_subprompt,
                    user_prompt=formatted_prompt
                ),
            }
        ],
        model=model,
    )

    response = chat_completion.choices[0].message.content
    # Parse the response to extract updated prompt, vocabulary, and features
    # Split by the "Story Request:" marker, accounting for possible preceding '\n\n'
    parts = response.split("Story Request:", 1)
    # Ensure "Story Request:" exists in the response
    if len(parts) > 1:
        # Extract updated prompt from the second part
        updated_prompt = '\nStory Request: ' + parts[1].strip()
    else:
        # Handle the case where "Story Request:" is not found
        updated_prompt = ""

    # Extract vocabulary and features from the second part (if it exists)
    if len(parts) > 1:
        second_part = parts[1]
        # Split and extract vocabulary and narratives, accounting for possible '\n\n' or direct markers
        if "Vocabulary:" in second_part:
            vocabulary_part = second_part.split("Vocabulary:", 1)[1].split("Narratives:", 1)[0].strip() if "Narratives:" in second_part else second_part.split("Vocabulary:", 1)[1].strip()
        else:
            vocabulary_part = ""
        if "Narratives:" in second_part:
            features_part = second_part.split("Narratives:", 1)[1].strip()
        else:
            features_part = ""
        updated_vocabulary = vocabulary_part.strip()
        updated_features = features_part.strip()
    else:
        updated_vocabulary = ""
        updated_features = ""

    if not updated_prompt or not updated_vocabulary or not updated_features:
        # guard clause to prevent empty values using empty strings
        if not updated_prompt:
            updated_prompt = ""
        if not updated_vocabulary:
            updated_vocabulary = ""
        if not features:
            updated_features = ""
    print('updated story request:', updated_prompt)
    # logging the words, features, query, and response to the db's meta_prompt_data table

    add_to_meta_prompt_table(
        user_meta_prompt=formatted_prompt,
        prompt_vocabulary=vocabulary,
        prompt_narratives=features,
        model_meta_response=updated_prompt,
        model_meta_vocabulary=updated_vocabulary,
        model_meta_narratives=updated_features
    )
    return updated_prompt, updated_features, updated_vocabulary

story_gen_system_prompt = (
                    f"{language_handling_subprompt}"
                    "You are the writer for a storytelling AI that can generate children's stories based on a given prompt."
                    "You should take the user input and generate a new story based on it."
                    "The story should be appropriate for children and should be creative and engaging."
                    "You should return BOTH a title and a story in the following format:\n\n"
                    "TITLE: [Your creative, unique title for the story]\n\n"
                    "STORY: [The story content]\n\n"
                    "The title should be creative, unique, and descriptive - avoid generic titles like 'The Dragon' or 'Space Adventure'."
                    "Instead, use specific, imaginative titles like 'Sparky the Fire-Breathing Friend' or 'Journey to the Purple Moon'."
                    "Do not include phrases like 'Once upon a time' in the title."
                    "Limit the story to 100 words."
                )

def new_story_generator(query):
    """Generate a new story based on the user's query."""
    # Fetch vocabulary and narrative features from the query
    formatted_prompt, features, vocabulary = meta_prompt_generator(query)
    chat_completion = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": story_gen_system_prompt,
            },
            {
                "role": "user",
                "content": formatted_prompt,
            }
        ],
        model=model,
    )

    response = chat_completion.choices[0].message.content
    # logging the words, features, query, and response to the db's prompt_data table
    add_to_prompt_table(
        features=features,
        vocabulary=vocabulary,
        user_prompt=query,
        model_response=response
    )

    # Parse the response to extract title and story
    try:
        # Split by the STORY: marker
        parts = response.split(f"STORY:", 1)


        # Extract title from the first part
        title_part = parts[0].strip()
        title = title_part.replace("TITLE:", "").strip()
        
        # Extract story from the second part (if it exists)
        story = parts[1].strip() if len(parts) > 1 else response
        # If we couldn't parse properly, just return the original response
        if not title or not story:
            return response

        # Store the title in a global variable or database for later use
        # For now, we'll just return the story, but we'll modify app.py to handle the title

        return {"title": title, "story": story}
    except:
        # If parsing fails, return the original response
        return {"title": "New Story", "story": response}


def fetch_conversation_history(conversation_id):
    messages = Message.query.filter_by(
        conversation_id=conversation_id).order_by(Message.created_at).all()
    return messages


def update_conversation_history(conversation_id, extended_story):
    new_message = Message(
        conversation_id=conversation_id,
        sender_type=SenderType.MODEL,
        code=3,
        content=extended_story
    )
    db.session.add(new_message)
    db.session.commit()


def add_to_story(conversation_id, query):
    # Fetch the existing conversation history from the database using conversation_id
    conversation_history = fetch_conversation_history(conversation_id)
    ### print the conversation history and length
    # Extract the story and combine all messages into a single story string
    existing_story = ""
    existing_title = "Continued Story"
    story_chunks = []
    part_number = 0
    for message in reversed(conversation_history):
        if message.sender_type == SenderType.MODEL and message.code in [2, 3]:
            # Check if the content has a title format
            if "TITLE:" in message.content and "STORY," in message.content:
                
                parts = re.split(r"STORY, PART #\d+:", message.content, maxsplit=1)
                title_part = parts[0].strip()
                existing_title = title_part.replace("TITLE:", "").strip()
                story_part = parts[1].strip()
                # Append the story part to the list
                story_chunks.append(story_part)
                # Increment the part number
                part_number += 1
            else:
                existing_story = message.content
                part_number += 1

    # Combine the story chunks into a single string
    if story_chunks:
        existing_story = "\n".join(reversed(story_chunks))

    if not existing_story:
        return jsonify({"message": "No existing story found in the conversation history."})
    # format the existing story and the current query for extendiing with new vocabulary and features
    contextual_query = f"Existing Title: {existing_title}\nExisting Story: {existing_story}\nStory Request: {query}"
    # Fetch vocabulary and narrative features from the query
    feature_vocabulary_prompt, features, vocabulary = meta_prompt_generator(contextual_query)
    print('### Continued Story Contextual Query:', contextual_query)
    # Generate the extended story by appending the new query
    chat_completion = client.chat.completions.create(
        messages=[
            {
                "role": "system",
                "content": (
                    f"{language_handling_subprompt}"
                    "You are the writer for a storytelling AI that can generate children's stories based on a given prompt."
                    "You should take the existing story and the new user input to generate an extended story."
                    "The story should be appropriate for children and should be creative and engaging."
                    "You should return BOTH the original title and the extended story in the following format:\n\n"
                    "TITLE: [Keep the original title]\n\n"
                    "STORY: [The extended story content]\n\n"
                    "Limit the extended part of the story to 100 words."
                    "This should be a NEW addition to the story, and it should be consistent with the existing story. Avoid reiterating previously mentioned details."
                    
                ),
            },
            {
                "role": "user",
                "content": f"Existing Title: {existing_title}\nExisting Story: {existing_story}\nStory Request: {feature_vocabulary_prompt}",
            }
        ],
        model=model,
    )

    response = chat_completion.choices[0].message.content

    # logging the words, features, query, and response to the db's prompt_data table
    add_to_prompt_table(
        features=features,
        vocabulary=vocabulary,
        user_prompt=query,
        model_response=response
    )

    # Parse the response to extract title and story
    try:
        # Split by the STORY: marker
        parts = response.split(f"STORY:", 1)

        # Extract title from the first part
        title_part = parts[0].strip()
        title = title_part.replace("TITLE:", "").strip()

        # Extract story from the second part (if it exists)
        story = parts[1].strip() if len(parts) > 1 else response

        # If we couldn't parse properly, just return the original response
        if not title or not story:
            return response

        # Return both title and story
        return {"title": title, "story": story, "part": part_number+1}
    except:
        # If parsing fails, return the original response
        return {"title": existing_title, "story": response}

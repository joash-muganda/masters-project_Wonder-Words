#!/usr/bin/env python
# coding: utf-8

# In[ ]:


import mysql.connector
from mysql.connector import Error
import pandas as pd
from db import db, Conversation, Message, SenderType
from flask import Flask
from dotenv import load_dotenv
import os
import re


# In[7]:


# loading environment variables from .env
load_dotenv()
host = os.getenv("DB_HOST")
user = os.getenv("DB_USER")
password = os.getenv("DB_PASSWORD")
database = os.getenv("DB_NAME")


# In[12]:


try:
    # Establish the connection
    connection = mysql.connector.connect(
        host=host,
        database=database,
        user=user,
        password=password
    )

    if connection.is_connected():
        print("Connected to the database")

except Error as e:
    print(f"Error: {e}")


# In[ ]:


# Create a cursor to execute  queries
cursor = connection.cursor()

# Execute a query to fetch data from the conversation and message tables
query = """
SELECT 
    c.id AS conversation_id, 
    c.created_at, 
    m.id AS message_id, 
    m.code, 
    m.sender_type, 
    m.content
FROM conversation c
JOIN message m ON c.id = m.conversation_id
"""

cursor.execute(query)
# Fetch all rows from the executed query
rows = cursor.fetchall()

#  save as a pandas dataframe
df = pd.DataFrame(rows, columns=['conversation_id', 'created_at', 'message_id', 'code', 'sender_type', 'content'])


# In[18]:


# Close the connection
if connection.is_connected():
    connection.close()
    print("Database connection closed")


# In[149]:


df.head()


# In[ ]:


# define the functions using regex to extract the data from the dataframe
import re
def extract_title(content):
    match = re.search(r'TITLE:\s*(.*?)\n\n', content)
    return match.group(1) if match else None
def identify_prompt(df_row):
    # check if column value for sender_type is 'user'
    if df_row.sender_type == 'USER':
        # if the content contains 'prompt evaluation request' return 'meta_prompt'
        match = re.search(r'prompt evaluation request\s*(.*)', df_row.content)
        return 'meta_prompt' if match else 'prompt'
def identify_response(df):
     # group by the conversation_id, and if there is another message with senter_type 'user' and 'prompt_type' is not null, return  the value + '_response'
    grouped = df.groupby('conversation_id')
    response = {}
    for name, group in grouped:
        user_message = group[group['sender_type'] == 'USER']
        prompt_type = user_message['prompt_type'].iloc[0] if not user_message.empty else None
        if prompt_type:
            response[name] = prompt_type
        else:
            response[name] = 'prompt'
    # now map the response type to the original dataframe, if sender_type is 'MODEL' append '_response' to the prompt_type
    df['prompt_type'] = df['conversation_id'].map(response)
    df.loc[df['sender_type'] == 'MODEL', 'prompt_type'] += '_response'
    return df['prompt_type']
       
def title_to_words(title):
    # split the title by spaces and return the list of words
    return title.split() if title else []
def extract_features(df_row):
    '''if the sender_type is 'user' and the content contains any feature in the features list 
    returns the features contained'''
    features = [
        "dragons", "space", "animals", "magic", "pirates", 
        "dinosaurs", "fairy_tale", "adventure"
    ]
    if df_row.sender_type == 'USER':
        found_features = [feature for feature in features if feature in df_row.content.lower()]
        return found_features if found_features else None
    return None


# In[ ]:


# identifying whether the content is a prompt or meta_prompt
df['prompt_type'] = df.apply(identify_prompt, axis=1)
# identifying the response
df['prompt_type'] = identify_response(df)


# In[156]:


# creating subsets of the dataframe for meta_prompt and prompt
meta_prompt_df = df[df['prompt_type'].str.startswith('meta_prompt', na=False)].dropna(how='all')
prompt_df = df[df['prompt_type'].str.startswith('prompt', na=False)].dropna(how='all')
# checking that the sum of the two subsets is equal to the original dataframe
assert len(df) == len(meta_prompt_df) + len(prompt_df), "Dataframe subsets do not sum up to the original dataframe length"


# In[157]:


# resetting the index of the dataframes
meta_prompt_df.reset_index(drop=True, inplace=True)
prompt_df.reset_index(drop=True, inplace=True)


# In[158]:


# creating a column for title, prompt, features and vocabulary
prompt_df.loc[:,'title'] = prompt_df['content'].apply(extract_title)
prompt_df['vocabulary'] = prompt_df['title'].apply(title_to_words)
prompt_df.loc[:,'features'] = prompt_df.apply(extract_features, axis=1)


# In[159]:


# selecting the relevant columns for the prompt dataframe
prompt_df = prompt_df.loc[:, ['sender_type', 'conversation_id','features','vocabulary', 'content']]


# In[179]:


# split the prompt_df into two dataframes, one for the user and one for the model
user_prompt_df = prompt_df[prompt_df['sender_type'] == 'USER'].drop(columns=['sender_type'])
model_prompt_df = prompt_df[prompt_df['sender_type'] == 'MODEL'].drop(columns=['sender_type'])
# join the user and model prompt dataframes on the conversation_id
merged_prompt_df = pd.merge(user_prompt_df, model_prompt_df, on='conversation_id', suffixes=('_user', '_model'))
# renaming the columns for clarity
merged_prompt_df.rename(columns={
    'content_user': 'user_prompt',
    'content_model': 'model_response',
    'features_user': 'features',
    'vocabulary_model': 'vocabulary'
}, inplace=True)
# selecting the relevant columns for the merged dataframe
merged_prompt_df = merged_prompt_df.loc[:, ['conversation_id', 'features', 'vocabulary', 'user_prompt', 'model_response']]
merged_prompt_df.reset_index(drop=True, inplace=True)


# In[180]:


merged_prompt_df


# In[181]:


# split the meta_prompt_df into two dataframes, one for the user and one for the model
user_meta_prompt_df = meta_prompt_df[meta_prompt_df['sender_type'] == 'USER'].drop(columns=['sender_type'])
model_meta_prompt_df = meta_prompt_df[meta_prompt_df['sender_type'] == 'MODEL'].drop(columns=['sender_type'])
# join the user and model meta_prompt dataframes on the conversation_id
merged_meta_prompt_df = pd.merge(user_meta_prompt_df, model_meta_prompt_df, on='conversation_id', suffixes=('_user', '_model'))
# renaming the columns for clarity
merged_meta_prompt_df.rename(columns={
    'content_user': 'user_meta_prompt',
    'content_model': 'model_meta_response'
}, inplace=True)
# selecting the relevant columns for the merged dataframe
merged_meta_prompt_df = merged_meta_prompt_df.loc[:, ['conversation_id', 'user_meta_prompt', 'model_meta_response']]
merged_meta_prompt_df.reset_index(drop=True, inplace=True)


# In[182]:


merged_meta_prompt_df


# In[170]:


# connect to the database
try:
    # Establish the connection
    connection = mysql.connector.connect(
        host=host,
        database=database,
        user=user,
        password=password
    )

    if connection.is_connected():
        print("Connected to the database")

except Error as e:
    print(f"Error: {e}")


# In[183]:


# convert the vocabulary column to a string list for insertion into the database
merged_prompt_df['vocabulary'] = merged_prompt_df['vocabulary'].apply(lambda x: ', '.join(x) if isinstance(x, list) else None)
# replace empty lists with None
merged_prompt_df['vocabulary'] = merged_prompt_df['vocabulary'].apply(lambda x: None if x == [] else x)
# convert the features column to a string list for insertion into the database
merged_prompt_df['features'] = merged_prompt_df['features'].apply(lambda x: ', '.join(x) if isinstance(x, list) else None)
# replace empty lists with None
merged_prompt_df['features'] = merged_prompt_df['features'].apply(lambda x: None if x == [] else x)


# In[ ]:


merged_prompt_df.drop(columns=['conversation_id'], inplace=True)


# In[198]:


merged_prompt_df.head()


# In[199]:


# Create a cursor to execute queries
cursor = connection.cursor()
# Insert the merged prompt data into the database as a new table
create_table_query = """
CREATE TABLE prompt_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    features TEXT,
    vocabulary TEXT,
    user_prompt TEXT,
    model_response TEXT
)
"""
cursor.execute("DROP TABLE IF EXISTS prompt_data")
cursor.execute(create_table_query)
# Insert the data into the prompt_data table

insert_query = """
INSERT INTO prompt_data (features, vocabulary, user_prompt, model_response)
VALUES (%s, %s, %s, %s)
"""
for index, row in merged_prompt_df.iterrows():
    cursor.execute(insert_query, tuple(row))
connection.commit()


# In[202]:


merged_meta_prompt_df.drop(columns=['conversation_id'], inplace=True)


# In[203]:


merged_meta_prompt_df


# In[204]:


# insert the meta prompt data into the database as a new table
create_meta_table_query = """
CREATE TABLE meta_prompt_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_meta_prompt TEXT,
    model_meta_response TEXT
)
"""
cursor.execute("DROP TABLE IF EXISTS meta_prompt_data")
cursor.execute(create_meta_table_query)
# Insert the data into the meta_prompt_data table
insert_meta_query = """
INSERT INTO meta_prompt_data (user_meta_prompt, model_meta_response)
VALUES (%s, %s)
"""
for index, row in merged_meta_prompt_df.iterrows():
    cursor.execute(insert_meta_query, tuple(row))
connection.commit()


# In[ ]:





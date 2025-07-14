#!/usr/bin/env python
# coding: utf-8

# In[1]:


import boto3
import sagemaker
from sagemaker.feature_store.feature_group import FeatureGroup


# In[2]:


import os
import s3fs
from datasets import load_dataset, load_dataset_builder
import pandas as pd
import re


# In[3]:


account_id = boto3.client("sts").get_caller_identity()["Account"]
print(account_id)


# ## Instantiating Sagemaker Feature Group / Database Object

# In[4]:


from sagemaker.session import Session

region = boto3.Session().region_name

boto_session = boto3.Session(region_name=region)

sagemaker_client = boto_session.client(service_name="sagemaker", region_name=region)
featurestore_runtime = boto_session.client(
    service_name="sagemaker-featurestore-runtime", region_name=region
)


# In[5]:


feature_store_session = Session(
    boto_session=boto_session,
    sagemaker_client=sagemaker_client,
    sagemaker_featurestore_runtime_client=featurestore_runtime,
)


# In[6]:


default_s3_bucket_name = feature_store_session.default_bucket()
prefix = "tinystories"


# In[7]:


train_fg = 'tinystories-train'
val_fg = 'tinystories-val'


# In[8]:


train_feature_group = FeatureGroup(
    name=train_fg, sagemaker_session=feature_store_session
)
val_feature_group = FeatureGroup(
    name=val_fg, sagemaker_session=feature_store_session
)


# ## Preparing the Data from HuggingFace

# In[9]:


hf_repo = 'Alexis-Az/TinyStories'


# In[10]:


train_df = load_dataset(hf_repo, revision='refs/convert/parquet', data_dir='default/train')


# In[11]:


val_df = load_dataset(hf_repo, revision='refs/convert/parquet', data_dir='default/validation')


# In[12]:


val_df


# In[13]:


train_df = pd.DataFrame(train_df['train'])
val_df = pd.DataFrame(val_df['train'])


# ### Adding the data type identifiers for the pandas columns

# In[14]:


def cast_object_to_string(data_frame):
    for label in data_frame.columns:
        if data_frame.dtypes[label] == "object":
            data_frame[label] = data_frame[label].astype("str").astype("string")


# In[15]:


cast_object_to_string(train_df)
cast_object_to_string(val_df)


# In[16]:


import time
current_time_sec = int(round(time.time()))


# In[17]:


train_df["timestamp"] = pd.Series([current_time_sec]*len(train_df), dtype="float64")
val_df["timestamp"] = pd.Series([current_time_sec]*len(val_df), dtype="float64")


# In[18]:


train_feature_group.load_feature_definitions(train_df)
val_feature_group.load_feature_definitions(val_df)


# In[19]:


def clean_strings(df):
    for label in df.columns:
        if df.dtypes[label] == "string":
            df[label] = df[label].apply(
                lambda x: re.sub('\n', ' ', str(x)))


# In[20]:


clean_strings(train_df)
clean_strings(val_df)


# ## Linking the Data from HF to the Database

# In[21]:


from sagemaker import get_execution_role

# You can modify the following to use a role of your choosing. See the documentation for how to create this.
role = get_execution_role()


# In[22]:


record_identifier_feature_name = "unique_id"
event_time_feature_name = "timestamp"


# In[28]:


def wait_for_feature_group_creation_complete(feature_group):
    status = feature_group.describe().get("FeatureGroupStatus")
    while status == "Creating":
        print("Waiting for Feature Group Creation")
        time.sleep(5)
        status = feature_group.describe().get("FeatureGroupStatus")
    if status != "Created":
        raise RuntimeError(f"Failed to create feature group {feature_group.name}")
    print(f"FeatureGroup {feature_group.name} successfully created.")


train_feature_group.create(
    s3_uri=f"s3://{default_s3_bucket_name}/{prefix}",
    record_identifier_name=record_identifier_feature_name,
    event_time_feature_name=event_time_feature_name,
    role_arn=role,
    enable_online_store=True,
)

val_feature_group.create(
    s3_uri=f"s3://{default_s3_bucket_name}/{prefix}",
    record_identifier_name=record_identifier_feature_name,
    event_time_feature_name=event_time_feature_name,
    role_arn=role,
    enable_online_store=True,
)

wait_for_feature_group_creation_complete(feature_group=train_feature_group)
wait_for_feature_group_creation_complete(feature_group=val_feature_group)


# In[24]:


output_dir = f"s3://{default_s3_bucket_name}/{prefix}"
output_dir


# ### Uploading to AWS GlueDB

# In[31]:


#saving the data from the huggingface repo to aws
train_feature_group.ingest(data_frame=train_df, max_workers=100, wait=True)


# In[32]:


#saving the data from the huggingface repo to aws
val_feature_group.ingest(data_frame=val_df, max_workers=100, wait=True)


# ## Sample Query of the Data

# In[33]:


train_query = train_feature_group.athena_query()
train_table = train_query.table_name


# In[34]:


val_query = val_feature_group.athena_query()
val_table = val_query.table_name


# In[35]:


query_string = (
    'SELECT * FROM "'
    + train_table
    + '"LIMIT 100;'
)
print("Running " + query_string)


# In[36]:


train_query.run(
    query_string=query_string,
    output_location="s3://" + default_s3_bucket_name + "/" + prefix + "/query_results/",
)
train_query.wait()
dataset = train_query.as_dataframe()


# In[38]:


dataset.sample(5)


# In[39]:


#the names of the tables in gluedb
print(train_table)
print(val_table)


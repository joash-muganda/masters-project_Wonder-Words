#!/usr/bin/env python
# coding: utf-8

# In[1]:


from pyspark.sql import SparkSession
from pyspark.sql.functions import monotonically_increasing_id, current_timestamp
from datasets import load_dataset, Dataset, DatasetDict
import huggingface_hub


# # ETL of Large Source Dataset
# Before uploading the dataset into a database and dataloading pipeline, the data has to be converted into I.I.E (independent and identifiable data) form by including a unique I.D and timestamp for each row. The data will also be split into its' train and validation subsets.

# In[2]:


get_ipython().run_line_magic('load_ext', 'sagemaker_studio_analytics_extension.magics')
get_ipython().run_line_magic('sm_analytics', 'emr-serverless connect --application-id 00fq6j1a0fiulq09 --language python --emr-execution-role-arn arn:aws:iam::597161074694:role/service-role/AmazonEMR-ServiceRole-20250211T131858')


# ## Connecting to PySpark
# Since the data is large (~2 million rows), processing the data in a distributed cluster will speed up processing.

# In[3]:


spark = SparkSession.builder \
    .master('local[*]') \
    .config("spark.driver.memory", "50g") \
    .appName('spark') \
    .getOrCreate()


# In[4]:


tinystories = "skeskinen/TinyStories-GPT4"
train_data = load_dataset(tinystories, revision = 'refs/convert/parquet',split="train[:2196080]")
val_data = load_dataset(tinystories, revision = 'refs/convert/parquet', split="train[2196080:]")


# In[5]:


train_data


# In[6]:


val_data


# In[7]:


train_data = spark.createDataFrame(train_data)


# In[8]:


val_data = spark.createDataFrame(val_data)


# ## Unique ID and Timestamp
# Adding these columns will make the records in the dataset independently identifiable for use with a database in AWS.

# In[9]:


# Add columns with PySpark UDFs
train_data = train_data.withColumn("unique_id", monotonically_increasing_id()) 
train_data = train_data.withColumn("timestamp", current_timestamp())


# In[10]:


# Add columns with PySpark UDFs
val_data = val_data.withColumn("unique_id", monotonically_increasing_id()) 
val_data = val_data.withColumn("timestamp", current_timestamp())


# ## Features and Words
# These columns were originally formatted in array data structures, and need to be converted to string format to allow for use with the training pipeline for language models.

# In[15]:


def features_to_string(arr):
    kind = 'narrative features: '
    return kind + ", ".join(arr)


# In[16]:


from pyspark.sql.functions import col, udf
from pyspark.sql.types import StringType


# In[17]:


features_to_string = udf(features_to_string)


# In[39]:


train_data = train_data.withColumn('string_features', features_to_string(col('features')))


# In[40]:


val_data = val_data.withColumn('string_features', features_to_string(col('features')))


# In[33]:


def words_to_string(arr):
    kind = 'vocabulary features: '
    return kind + ", ".join(arr)


# In[34]:


words_to_string = udf(words_to_string)


# In[35]:


train_data = train_data.withColumn('string_words', words_to_string(col('words')))
val_data = val_data.withColumn('string_words', words_to_string(col('words')))


# In[46]:


train_data = train_data.drop('words').drop('features')
val_data = val_data.drop('words').drop('features')


# In[50]:


train_data.printSchema()


# ## Uploading to HuggingFace

# In[51]:


#converting to huggingface dataset objects
train_data = Dataset.from_spark(train_data)
val_data = Dataset.from_spark(val_data)


# In[52]:


df_splits = {'train': train_data, 'validation': val_data}


# In[53]:


repo_id = 'Alexis-Az/TinyStories'


# In[54]:


full_data = DatasetDict(df_splits)


# In[55]:


full_data.push_to_hub(repo_id=repo_id)


# In[ ]:





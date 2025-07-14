#!/usr/bin/env python
# coding: utf-8

# In[1]:


import torch
from transformers import AutoTokenizer
import numpy as np
from sagemaker.serve.spec.inference_spec import InferenceSpec


# # Testing Loading of the Compiled Model 
# This is the model that was deployed to AWS using the model's torch.jit.trace .pth object. In this notebook the model is loaded using torch.jit.load which is what AWS uses in their PyTorch image container environment. This model is large so it cannot be uploaded using the AWS sagemaker GUI so instead, the model artifacts where saved in a AWS S3 bucket and the path used as the input for the model in sagemaker's deployable model action. The huggingface environment variable HF_TASK for text-generation was added and then tested by scanning the logs using AWS cloudwatch. Model loading errors occured due to other issues (does not exist when loading in this notebook). **The model was deployed to an AWS container using huggingface endpoint's GUI using the repo containing the finetuned model. Note that the model's 'generate' method used to generate text was not traced due to untracable modules used in the generate method.**

# In[2]:


model = torch.jit.load('./serve/Story-Generation-Model.pt')


# In[3]:


tokenizer = AutoTokenizer.from_pretrained("Alexis-Az/Story-Generation-Model")


# In[4]:


DUMMY_TEXT = "Hi! Can you tell me a story about a cute park?"


# In[5]:


class InferenceSpec(InferenceSpec):
    def invoke(self, input_object: object, model: object):       
        with torch.no_grad():
            output = model(input_object, True)
        return output
        
    def load(self, model_dir: str):
        model = torch.jit.load(model_dir+f"/{INFER_MODEL.split('/')[-1]}.pt")
        model.eval()
        return model

inf_spec = InferenceSpec()


# In[6]:


get_ipython().run_cell_magic('capture', '', 'model.eval()\n')


# In[7]:


tokens = tokenizer(DUMMY_TEXT, return_tensors='pt')


# In[8]:


tokens


# In[15]:


output


# In[ ]:





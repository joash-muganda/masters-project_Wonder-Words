#!/usr/bin/env python
# coding: utf-8

# In[1]:


from safetensors.torch import load_file
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM
#from peft import LoraConfig, get_peft_model
from sagemaker.pytorch import PyTorch
import numpy as np
import torch.nn as nn
import shutil


# In[2]:


get_ipython().system('pip install sentencepiece')
get_ipython().system('pip install tiktoken')


# In[3]:


import transformers
import sentencepiece


# In[4]:


transformers.__version__


# In[5]:


from sagemaker.serve.builder.model_builder import ModelBuilder
from sagemaker.serve.builder.schema_builder import SchemaBuilder
from safetensors.torch import load_file
import torch
from sagemaker.serve.mode.function_pointers import Mode
from transformers import AutoTokenizer, AutoModelForCausalLM
from sagemaker import get_execution_role, Session, image_uris
from sagemaker.serve import InferenceSpec
import boto3
from sagemaker.serve import CustomPayloadTranslator
import torch
from torchvision.transforms import transforms
from sagemaker.serve.spec.inference_spec import InferenceSpec
from transformers import pipeline
from sagemaker.serve import ModelServer
from sagemaker.pytorch import PyTorchModel
import sagemaker
from pathlib import Path
import numpy as np
import io
import os
sagemaker_session = Session()
region = boto3.Session().region_name

# get execution role
# please use execution role if you are using notebook instance or update the role arn if you are using a different role
execution_role = get_execution_role() if get_execution_role() is not None else "your-role-arn"


# In[6]:


from transformers import LlamaForCausalLM


# In[7]:


#%%capture
#!pip install -U accelerate


# In[8]:


SAVED_MODEL = "Alexis-Az/Story-Generation-LlaMA-3.1-8B-10k"
INFER_MODEL= "Alexis-Az/Story-Generation-Model"
max_seq_length = 1024


# # The PEFT Weighted Merged Model 
# In this notebook the peft/lora finetuned model that was finetuned on the tiny stories dataset was formatted successfully and unsuccessfully for deployment. The finetuned models weights were merged so that the lora weights were merged with the original weights as the first step prior to inference so that the model was making predictions based on the full knowledge. **Ultimately, the notebooks used for model deployment in Sagemaker are a work-in-progress experiment to test Sagemaker's API in python for model deployment strategy.**
# 
# ## Formatting Results
# 
# The model was successfully formatted to both a weights dictionary file, as well as a torch.jit .pt model file. The torch.script.trace method is used to compile a model for deployment and is recommended by aws/sagemaker. The model was unsuccessfully deployed to an AWS sagemaker container using their ModelBuilder api methods however, due to multiple causes - a mismatch in model loading method using the recommended AWS image used for inference and the model class used. **Instead, to deploy the LLM, the model is deployed using HuggingFace's endpoint GUI by using the non-formatted model repo containing the merged lora weights and tokenizer.**
# 
# ### Note:
# It is not recommended to run this notebook in a AWS Sagemaker domain spaces environment fully. Firstly, sections of this code work given authentication so a user should be logged in to their own domain. Secondly, sections of this code contain errors due to the environment/container requested by the ModelBuilder during deployment do not align with the model loading method used within the "Story-Generation-LlaMA-3.1-8B-10k" model.

# ## Loading the Finetuned Model
# SAVED_MODEL is the lora huggingface repo of the peft model that has been fine-tuned. INFER_MODEL is the huggingface repo of the model that has the lora weights merged with the base weights for inferring. The model was pushed to the INFER_MODEL huggingface repo, and will be formatted for inference here. To have the model be able to be loaded in a HF TGI inference server, the model's flash attention should be turned off by using the cpu instead of the gpu.

# In[ ]:


import unsloth


# In[ ]:


adapter_model, tokenizer = unsloth.FastLanguageModel.from_pretrained(SAVED_MODEL, load_in_4bit=True)


# In[ ]:


adapter_model.save_pretrained_merged("Story-Generation-LlaMA-3.1-8B-10k", tokenizer)


# In[ ]:


adapter_model


# In[ ]:


pth_model = AutoModelForCausalLM.from_pretrained("Story-Generation-LlaMA-3.1-8B-10k")


# In[12]:


tokenizer = AutoTokenizer.from_pretrained("Story-Generation-LlaMA-3.1-8B-10k")


# In[ ]:


pth_model.push_to(
    INFER_MODEL,
    tokenizer=tokenizer,
    safe_serialization=True,
    create_pr=True,
    max_shard_size="3GB",
)


# In[49]:


from tokenizers.pre_tokenizers import Whitespace
from transformers import convert_slow_tokenizer


# In[56]:


from transformers import LlamaTokenizerFast


# In[48]:


tokenizer.push_to_hub(INFER_MODEL)


# ### Attempt #1: Scripting the Model as a .pth TorchScript file
# **Note: This section will not run unless using a container using large GPU memory and disk size to store a model in GPU memory, and to store the model file on disk.**

# In[74]:


tokenizer = AutoTokenizer.from_pretrained(INFER_MODEL)


# In[ ]:


tokenizer = LlamaTokenizer.from_pretrained('./test_tokenizer')


# In[65]:


class TritonWrapper(nn.Module):
    
    def __init__(self, model_name: str):
        super().__init__()

        self.model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torchscript=True,
            torch_dtype=torch.float16,
            trust_remote_code=True,
            device_map='auto'
            )
        self.model.output_hidden_states = False
                
    def forward(self, input_ids):
        self.model.eval()
        o = self.model(input_ids, output_hidden_states=False)
        return o[0]


# In[66]:


model = TritonWrapper(INFER_MODEL)
model.eval()


# In[67]:


DUMMY_TEXT = 'hi! can you tell me a story about sonic?'


# In[ ]:


batch = _tokenizer('hi! can you tell me a story about sonic?', return_tensors="pt")
output = _tokenizer.decode(model.model.generate(batch['input_ids'].cuda(), max_new_tokens=500)[0])


# In[80]:


output


# In[69]:


model.eval()


# In[22]:


model_dir = "./serve"


# In[ ]:


os.mkdir(model_dir)


# In[15]:


assert model.training == False
with torch.no_grad():
    model.model.eval()
    traced_model = torch.jit.trace(model, batch['input_ids'])
    print("traced_model done")
    torch.jit.save(traced_model, model_dir+f"/{INFER_MODEL.split('/')[-1]}.pt")


# # Using Sagemaker's 'ModelBuilder' Class to Format the PyTorch Model Artifacts

# This is the default code for the AWS SDK from HuggingFace's Deploy Action in their UI

# In[11]:


import json
from sagemaker.huggingface import HuggingFaceModel, get_huggingface_llm_image_uri


# In[ ]:


get_ipython().run_cell_magic('capture', '', '!pip install -U sagemaker\n')


# ## Attempt #2: Using the Huggingface ModelBuilder object

# In[32]:


# Hub Model configuration. https://huggingface.co/models
hub = {
	'HF_MODEL_ID':'Alexis-Az/Story-Generation-Model',
	'SM_NUM_GPUS': json.dumps(1),
    'SAGEMAKER_TS_RESPONSE_TIMEOUT':'600', 
    'SAGEMAKER_MODEL_SERVER_TIMEOUT':'600',
}



# create Hugging Face Model Class
huggingface_model = HuggingFaceModel(
	image_uri=get_huggingface_llm_image_uri("huggingface",version="3.0.1"),
	env=hub,
	role=execution_role, 
)


# In[33]:


# deploy model to SageMaker Inference
predictor = huggingface_model.deploy(
	initial_instance_count=1,
	instance_type="ml.g5.12xlarge",
	container_startup_health_check_timeout=300,
  )


# In[34]:


# send request
predictor.predict({
	"inputs": "Hi, what can you help me with?",
})


# ## Attempt #3: Using the Huggingface PiplineModelBuilder Class & Repo

# In[23]:


model_dir+f"/{INFER_MODEL.split('/')[-1]}.pt"


# In[24]:


from transformers import pipeline


# In[25]:


class InferenceSpec(InferenceSpec):
    def invoke(self, input_object: object, model: object):       
        return model(input_object)
        
    def load(self, model_dir: str):
        return pipeline('text-generation', "Alexis-Az/Story-Generation-Model", device_map='auto')

inf_spec = InferenceSpec()


# In[26]:


torch.__version__


# In[9]:


value: str = "Girafatron is obsessed with giraffes, the most glorious animal on the face of this Earth. Giraftron believes all other animals are irrelevant when compared to the glorious majesty of the giraffe.\nDaniel: Hello, Girafatron!\nGirafatron:"
schema = SchemaBuilder(value,
            {"generated_text": "Girafatron is obsessed with giraffes, the most glorious animal on the face of this Earth. Giraftron believes all other animals are irrelevant when compared to the glorious majesty of the giraffe.\\nDaniel: Hello, Girafatron!\\nGirafatron: Hi, Daniel. I was just thinking about how magnificent giraffes are and how they should be worshiped by all.\\nDaniel: You and I think alike, Girafatron. I think all animals should be worshipped! But I guess that could be a bit impractical...\\nGirafatron: That\'s true. But the giraffe is just such an amazing creature and should always be respected!\\nDaniel: Yes! And the way you go on about giraffes, I could tell you really love them.\\nGirafatron: I\'m obsessed with them, and I\'m glad to hear you noticed!\\nDaniel: I\'"})


# In[28]:


local_model_dir = str(Path(model_dir).resolve())


# In[29]:


package_dir = 'model.tar.gz'


# In[10]:


prompt = "The diamondback terrapin or simply terrapin is a species of turtle native to the brackish coastal tidal marshes of the"
response = "The diamondback terrapin or simply terrapin is a species of turtle native to the brackish coastal tidal marshes of the east coast."

sample_input = {
    "inputs": prompt,
    "parameters": {}
}

sample_output = [
    {
        "generated_text": response
    }
]


# In[43]:


instance_type = 'ml.c6a.12xlarge'
image = image_uris.retrieve(region=region, framework='huggingface',base_framework_version='pytorch2.0.0', version = '4.28',image_scope='inference', instance_type=instance_type)


# In[48]:


image = '763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-inference:2.0.0-transformers4.28.1-cpu-py310-ubuntu20.04'


# In[49]:


model_builder = ModelBuilder(mode=Mode.SAGEMAKER_ENDPOINT,model=INFER_MODEL,schema_builder=SchemaBuilder(sample_input, sample_output), model_path='./huggingface', env_vars={"HF_TASK":"text-generation"}, dependencies={"auto":True}, image_uri=image)


# In[50]:


_model = model_builder.build()


# In[ ]:


_model.deploy(role=execution_role, instance_type='ml.g4dn.8xlarge')


# ## Attempt 4: Using the ModelBuilder class and Compiling own Container (BYOC)
# The last attempt is the most tedious and less automated method which requires saving the model artifacts and using the sagemaker GUI to create the deployable model/the endpoint. **Note: deploy() in this section results in deployment errors potentially due to the model class used being a CAUSAL_LM model that AWS tries to load using a concrete FlashCausalLM class instead of the LLamaCausalLM class, or due to issues loading the lora weight merged model that has been finetuned using Unsloth. This section will not run unless using a container using large CPU memory.**

# In[35]:


model_builder = ModelBuilder(
    mode=Mode.SAGEMAKER_ENDPOINT,
    model_path=model_dir,
    inference_spec=inf_spec,
    role_arn=execution_role,
    image_uri=image,
    schema_builder=schema,
    env_vars={"HF_TASK":"text-generation"},
    model_server=ModelServer.TORCHSERVE
)


# In[23]:


_model = model_builder.build()


# In[ ]:


model.deploy()


# In[18]:


get_ipython().system('sudo apt install pigz')


# In[33]:


model_dir


# In[37]:


os.chdir(model_dir)


# In[39]:


import subprocess

def create_tar_pigz(tar_filename, source_dir):
    # = f"tar -I pigz -cf {tar_filename} {source_dir}"
    #subprocess.run(command, shell=True, check=True)
    command = f"tar -I pigz -cf {tar_filename} {source_dir}"
    subprocess.run(command, shell=True, check=True) 


# packaging the model file itself as the top level 'directory'
create_tar_pigz('../'+package_dir, '.')


# In[41]:


os.chdir('..')


# In[42]:


import boto3

# Create an S3 client
s3 = boto3.client('s3', region_name=region)  # Replace 'YOUR_REGION' with your bucket's region

bucket_name = 'unsloth-finetuned'      # Name of your S3 bucket

try:
    # Upload the file
    s3.upload_file(package_dir, bucket_name, package_dir)
except Exception as e:
    print(f"Error uploading file: {e}")


# In[ ]:





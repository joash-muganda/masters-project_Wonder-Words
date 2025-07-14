# Sagemaker Model Case Study and Training Notebooks
In this directory, the AWS Sagemaker service for model building and deployment orchestration is used to finetune the Llama 3.1 8B Instruct model from Unsloth in the '1_Finetuning_Story_Generation' notebook. The source data is a storytelling dataset known as 'tinystories' publically available and hosted on HuggingFace. The model was formatted for deployment using the Sagemaker API in the '2_format_model' notebook, prior to deployment using the HuggingFace API/GUI in an AWS inference endpoint. The data from the formatted data repo in huggingface is uploaded to an AWS Gluedb database in '3_load_db' for future instruction fine-tuning using user story requests. The '4_load_model' notebook was used to load and test the torch.script format used by AWS for scalable model deployment. Furthermore, the 'Insights' & 'Metrics' case study notebooks calculate and assess relevant metrics related to WonderWords' creativity, literacy, and mental health objectives.

## HuggingFace Data and Model Links
| Data Repos | Model Repos |
|---|---|
| Source Data: https://huggingface.co/datasets/skeskinen/TinyStories-GPT4 | Non-quantized: https://huggingface.co/Alexis-Az/Story-Generation-LlaMA-3.1-8B-10k |
| Formatted Data: https://huggingface.co/datasets/Alexis-Az/TinyStories |  Quantized: https://huggingface.co/Alexis-Az/Story-Generation-LlaMA-3.1-8B-10k-GGUF |


*Private Model Package (tar file of inference_container/serve): s3://unsloth-finetuned/model.tar.gz*

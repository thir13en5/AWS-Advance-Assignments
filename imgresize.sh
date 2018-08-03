#!/bin/bash
#ASSIGNMENT 3: Advance AWS : Scalable architechure for image resize into 200 x 200
#make image source bucket
git clone https://github.com/thir13en5/AWS-Advance-Assignments.git
cd AWS-Advance-Assignments/

aws s3 mb s3://cdm-img-bucket --region us-east-1

#storing my lambda function code in a file with appropriate name
echo "import boto3 
from io import BytesIO
from os import path
import PIL
from PIL import Image
s3 = boto3.resource('s3')
origin_bucket = 'cdm-img-bucket'
destination_bucket = 'cdm-img-bucket'


def lambda_handler(event, context):
    object_key = event['Records'][0]['s3']['object']['key']
    if 'resized_' not in object_key:
        extension = path.splitext(object_key)[1].lower()
        obj = s3.Object(bucket_name=origin_bucket, key=object_key)
        obj_body = obj.get()['Body'].read()
        if extension in ['.jpeg', '.jpg']:
            format = 'JPEG'
        if extension in ['.png']:
            format = 'PNG'
        img = Image.open(BytesIO(obj_body))
        img = img.resize((200, 200))
        buffer = BytesIO()
        img.save(buffer, format)
        buffer.seek(0)
        obj = s3.Object(bucket_name=destination_bucket, key='resized_'+object_key)
        obj.put(Body=buffer)" > lambda_function.py

#zipping my code and related libraries 
zip -r code.zip lambda_function.py PIL Pillow-4.2.0.data Pillow-4.2.0.dist-info

echo "Created zip file and lambda_function code"

echo "Creating Lambda Function"

aws lambda create-function --function-name cdm-img-resize \
--runtime python3.6 \
--role arn:aws:iam::488599217855:role/FullAccess \
--handler lambda_function.lambda_handler \
--zip-file fileb://code.zip \
--timeout 300 \
--region us-east-1

echo "Lambda function created..\nAdding Permissions"
aws lambda add-permission \
--function-name cdm-img-resize \
--region "us-east-1" \
--statement-id "1" \
--action "lambda:InvokeFunction" \
--principal s3.amazonaws.com \
--source-arn arn:aws:s3:::cdm-img-bucket 

echo "Getting ARN for the lambda function"
arn=$(aws lambda get-function-configuration --function-name cdm-img-resize --region us-east-1 --query '{FunctionArn:FunctionArn}' --output text)
echo $arn
echo "Adding events json file for S3 trigger"

echo "{
  \"LambdaFunctionConfigurations\": [
    {
      \"LambdaFunctionArn\":"\""$arn"\"",
      \"Events\": [\"s3:ObjectCreated:*\"]
    }
  ]
}" > events.json

echo "Permission added\nAdding S3 trigger..."
aws s3api put-bucket-notification-configuration \
--bucket cdm-img-bucket \
--notification-configuration file://events.jsons

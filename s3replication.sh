aws s3 mb s3://cdmsrcbucket --region us-east-1
aws s3 mb s3://cdmdestbucket --region us-west-1
echo "Buckets Created.."

aws s3api put-bucket-versioning --bucket cdmsrcbucket --versioning-configuration Status=Enabled
aws s3api put-bucket-versioning --bucket cdmdestbucket --versioning-configuration Status=Enabled

echo "Versioning enabled "

echo "Adding Copy Lambda Code...."

echo "import boto3
import json
import time

s3 = boto3.client('s3')

REGION = 'us-east-1' # region to launch instance.
AMI = 'ami-b70554c8'
    # matching region/setup amazon linux ami, as per:
    # https://aws.amazon.com/amazon-linux-ami/
INSTANCE_TYPE = 't2.micro' # instance type to launch.

EC2 = boto3.client('ec2', region_name=REGION)
def lambda_handler(event, context):
    \"\"\" Lambda handler taking [message] and creating a httpd instance with an echo. \"\"\"
    #message = event['message']
    source_bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    #size = event['Records'][0]['s3']['object']['size']
    eventName = event['Records'][0]['eventName']
    print(source_bucket)
    print(key)
    #print(size)
    print(eventName)
    copy_source = {'Bucket':source_bucket, 'Key':key}
    target_bucket = 'cdmdestbucket'
    if eventName == 'ObjectCreated:Put':
        print (\"Copying object from Source S3 bucket to Traget S3 bucket \")
        s3.copy_object(Bucket=target_bucket, Key=key, CopySource=copy_source)
    if eventName == 'ObjectRemoved:DeleteMarkerCreated':
        s3.delete_object(Bucket=target_bucket, Key=key)
    return \"Hello\"" > copylambda.py
zip myfile.zip copylambda.py


echo "Created zip file and copylambda code"

echo "Creating Lambda Function"

aws lambda create-function --function-name cdm-copy-func \
--runtime python3.6 \
--role arn:aws:iam::488599217855:role/FullAccess \
--handler copylambda.lambda_handler \
--zip-file fileb://myfile.zip \
--timeout 300 \
--region us-east-1

echo "Lambda function created..\nAdding Permissions"
aws lambda add-permission \
--function-name cdm-copy-func \
--region "us-east-1" \
--statement-id "1" \
--action "lambda:InvokeFunction" \
--principal s3.amazonaws.com \
--source-arn arn:aws:s3:::cdmsrcbucket 

echo "Getting ARN for the lambda function"
aws lambda get-function-configuration --function-name cdm-copy-func \
--region us-east-1 > data.json
arn=$(python parse.py)
echo $arn
echo "Adding events json file for S3 trigger"

echo "{
  \"LambdaFunctionConfigurations\": [
    {
      \"LambdaFunctionArn\":"\""$arn"\"",
      \"Events\": [\"s3:ObjectCreated:*\"]
    },
    {
      \"LambdaFunctionArn\":"\""$arn"\"",
      \"Events\": [\"s3:ObjectRemoved:*\"]
    }
  ]
}" > events.json

echo "Permission added\nAdding S3 trigger..."
aws s3api put-bucket-notification-configuration \
--bucket cdmsrcbucket \
--notification-configuration file://events.json


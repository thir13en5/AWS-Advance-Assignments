import boto3 
from io import BytesIO
from os import path
import PIL
from PIL import Image
s3 = boto3.resource('s3')
origin_bucket = 'austin-practise'
destination_bucket = 'austin-practise'


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
        obj.put(Body=buffer)

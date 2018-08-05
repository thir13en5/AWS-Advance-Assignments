#!/bin/bash
#ASSIGNMENT 4: In order to cut costs company decides to start and stop their instances in certain intervals of time.
#	       The team should give the time intervals for the whole week at the starting of the week and EC2 instances should automatically start and stop accordingly.
#Following is how the solution can be implemented. A cloudwatch event for a particular day will trigger a lambda function to start and stop ec2 instances.
#Use cases covered: 1. The schedule is dynamic each day has its own different interval for ec2 instances.
#		    2. The user has the ability to change schedule on demand and also change the weekly schedule anytime.
#		    3. When no schedule given a default one should be followed.

#Making function files for start, stop and s3 

#START Function
echo "import json
import boto3
import calendar
import datetime

# Enter the region your instances are in. Include only the region without specifying Availability Zone; e.g.; 'us-east-1'
region = 'us-east-1'
# Enter your instances here:
instances = ['i-0cb18d568507537b0']

def lambda_handler(event, context):
    ec2 = boto3.client('ec2', region_name=region)
    ec2.start_instances(InstanceIds=instances)
    print ('started your instances: ' + str(instances))
    
    #getting next day
    today = datetime.datetime.now() + datetime.timedelta(days=1)
    next_day=today.strftime("%A")
    next_day=next_day[0:3]
    print(next_day)
    
    #changing rule
    client = boto3.client('s3')
    
    json_object = client.get_object(Bucket='s3-read-weekly', Key='weekly.json')
    print(json_object)
    jsonFileReader = json_object['Body'].read()
    print(jsonFileReader)
    jsonDict = json.loads(jsonFileReader)
    #print(type(jsonDict)
    cron=jsonDict[next_day][2]['cronstart']
    print(cron)
    
    c = boto3.client('events')
    
    response = c.put_rule(
           Name='cdm_start_rule',
           ScheduleExpression=cron,
           State='ENABLED'
           )
    
    return 'Hello from Lambda'
" > cdm-ec2-start.py

zip cdmec2start.zip cdm-ec2-start.py

rm cdm-ec2-start.py

aws lambda create-function --function-name cdm-ec2-start \
--runtime python3.6 \
--role arn:aws:iam::488599217855:role/FullAccess \
--handler cdm-ec2-start.lambda_handler \
--zip-file fileb://cdmec2start.zip \
--timeout 300 \
--region us-east-1

echo "Getting ARN for the start ec2 lambda function"
arnstart=$(aws lambda get-function-configuration --function-name cdm-ec2-start --region us-east-1 --query '{FunctionArn:FunctionArn}' --output text)

echo "Creating Cloudwatch event start rule for starting of EC2 instances"
aws events put-rule --name "cdm_start_rule"

echo "Adding lambda targets.."
aws events put-targets --rule "cdm_start_rule" --targets "Id"="1","Arn"="$arnstart" --region "us-east-1"

#DEFAULT RULE
start_rule_arn=$(aws events put-rule --name cdm_start_rule --schedule-expression "cron(0 20 * * ? *)" --role-arn "arn:aws:iam::488599217855:role/FullAccess" --region us-east-1 --query 'RuleArn' --output text)

aws lambda add-permission \
	--function-name cdm-ec2-start \
	--statement-id "1" \
	--action 'lambda:InvokeFunction' \
	--principal events.amazonaws.com \
	--source-arn $start_rule_arn \
	--region "us-east-1"

#STOP function
echo "import boto3
import json
import datetime
# Enter the region your instances are in. Include only the region without specifying Availability Zone; e.g., 'us-east-1'
region = 'us-east-1'
# Enter your instances here:
instances = ['i-0cb18d568507537b0']

def lambda_handler(event, context):
    
    today = datetime.datetime.now() + datetime.timedelta(days=1)
    next_day=today.strftime("%A")
    next_day=next_day[0:3]
    print(next_day)
    
    #changing rule
    client = boto3.client('s3')
    
    json_object = client.get_object(Bucket='s3-read-weekly', Key='weekly.json')
    print(json_object)
    jsonFileReader = json_object['Body'].read()
    print(jsonFileReader)
    jsonDict = json.loads(jsonFileReader)
    #print(type(jsonDict)
    cron=jsonDict[next_day][3]['cronstop']
    print(cron)
    
    c = boto3.client('events')
    
    response = c.put_rule(
           Name='cdm_stop_rule',
           ScheduleExpression=cron,
           State='ENABLED'
           )
    
    ec2 = boto3.client('ec2', region_name=region)
    ec2.stop_instances(InstanceIds=instances)
    print ('stopped your instances: ' + str(instances))" > cdm-ec2-stop.py

zip cdmec2stop.zip cdm-ec2-stop.py

rm cdm-ec2-stop.py

aws lambda create-function --function-name cdm-ec2-stop \
--runtime python3.6 \
--role arn:aws:iam::488599217855:role/FullAccess \
--handler cdm-ec2-stop.lambda_handler \
--zip-file fileb://cdmec2stop.zip \
--timeout 300 \
--region us-east-1

echo "Getting ARN for the stop ec2 lambda function"
arnstop=$(aws lambda get-function-configuration --function-name cdm-ec2-stop.py --region us-east-1 --query '{FunctionArn:FunctionArn}' --output text)

echo "Creating Cloudwatch event stop rule for stoping of EC2 instances"
aws events put-rule --name "cdm_stop_rule"

echo "Adding lambda targets.."
aws events put-targets --rule "cdm_stop_rule" --targets "Id"="2","Arn"="$arnstop" --region "us-east-1"

#DEFAULT RULE
stop_rule_arn=$(aws events put-rule --name cdm_stop_rule --schedule-expression "cron(0 21 * * ? *)" --role-arn "arn:aws:iam::488599217855:role/FullAccess" --region us-east-1 --query 'RuleArn' --output text)

aws lambda add-permission \
        --function-name cdm-ec2-stop \
        --statement-id "2" \
        --action 'lambda:InvokeFunction' \
        --principal events.amazonaws.com \
        --source-arn $stop_rule_arn \
        --region "us-east-1"

#S3 Function for ondemand requests and updation of weekly.json
echo "import boto3
import json
from datetime import date
import calendar
s3_client = boto3.client('s3')
client = boto3.client('events')
my_date = date.today()
today = calendar.day_name[my_date.weekday()]
#print(today)
def lambda_handler(event, context):
    bucket = event['Records'][0]['s3']['bucket']['name']
    json_file_name = event['Records'][0]['s3']['object']['key']
    #print(bucket)
    #print(json_file_name)
    json_object = s3_client.get_object(Bucket=bucket, Key=json_file_name)
    #print(json_object)
    jsonFileReader = json_object['Body'].read()
    #print(jsonFileReader)
    jsonDict = json.loads(jsonFileReader)
    #print(type(jsonDict))
    case = today[0:3]
    if case == 'Mon':
        cronstart = jsonDict['Mon'][2]['cronstart']
        cronstop = jsonDict['Mon'][3]['cronstop']
        response_start = client.put_rule(
            Name='cdm_start_rule',
            ScheduleExpression=cronstart,
            State='ENABLED'
            )
        response_stop = client.put_rule(
            Name='cdm_stop_rule',
            ScheduleExpression=cronstop,
            State='ENABLED'
            )
    elif case == 'Tue':
        cronstart = jsonDict['Tue'][2]['cronstart']
        cronstop = jsonDict['Tue'][3]['cronstop']
        response_start = client.put_rule(
            Name='cdm_start_rule',
            ScheduleExpression=cronstart,
            State='ENABLED'
            )
        response_stop = client.put_rule(
            Name='cdm_stop_rule',
            ScheduleExpression=cronstop,
            State='ENABLED'
            )
    elif case == 'Wed':
        cronstart = jsonDict['Wed'][2]['cronstart']
        cronstop = jsonDict['Wed'][3]['cronstop']
        response_start = client.put_rule(
            Name='cdm_start_rule',
            ScheduleExpression=cronstart,
            State='ENABLED'
            )
        response_stop = client.put_rule(
            Name='cdm_stop_rule',
            ScheduleExpression=cronstop,
            State='ENABLED'
            )
    elif case == 'Thu':
        cronstart = jsonDict['Thu'][2]['cronstart']
        cronstop = jsonDict['Thu'][3]['cronstop']
        response_start = client.put_rule(
            Name='cdm_start_rule',
            ScheduleExpression=cronstart,
            State='ENABLED'
            )
        response_stop = client.put_rule(
            Name='cdm_stop_rule',
            ScheduleExpression=cronstop,
            State='ENABLED'
            )
    elif case == 'Fri':
        cronstart = jsonDict['Fri'][2]['cronstart']
        cronstop = jsonDict['Fri'][3]['cronstop']
        response_start = client.put_rule(
            Name='cdm_start_rule',
            ScheduleExpression=cronstart,
            State='ENABLED'
            )
        response_stop = client.put_rule(
            Name='cdm_stop_rule',
            ScheduleExpression=cronstop,
            State='ENABLED'
            )
    elif case == 'Sat':
        cronstart = jsonDict['Sat'][2]['cronstart']
        cronstop = jsonDict['Sat'][3]['cronstop']
        response_start = client.put_rule(
            Name='cdm_start_rule',
            ScheduleExpression=cronstart,
            State='ENABLED'
            )
        response_stop = client.put_rule(
            Name='cdm_stop_rule',
            ScheduleExpression=cronstop,
            State='ENABLED'
            )
    elif case == 'Sun':
        cronstart = jsonDict['Sun'][2]['cronstart']
        cronstop = jsonDict['Sun'][3]['cronstop']
        response_start = client.put_rule(
            Name='cdm_start_rule',
            ScheduleExpression=cronstart,
            State='ENABLED'
            )
        response_stop = client.put_rule(
            Name='cdm_stop_rule',
            ScheduleExpression=cronstop,
            State='ENABLED'
            )
    return 'Hello from Lambda'
    " > cdm-s3-read-weekly.py

zip cdms3.zip cdm-s3-read-weekly.py

rm cdm-s3-read-weekly.py

aws lambda create-function --function-name cdm-s3-read-weekly \
--runtime python3.6 \
--role arn:aws:iam::488599217855:role/FullAccess \
--handler cdm-s3-read-weekly.lambda_handler \
--zip-file fileb://cdms3.zip \
--timeout 300 \
--region us-east-1

echo "Getting ARN for the S3 lambda function"
arns3=$(aws lambda get-function-configuration --function-name cdm-s3-read-weekly --region us-east-1 --query '{FunctionArn:FunctionArn}' --output text)

aws lambda add-permission \
--function-name cdm-s3-read-weekly \
--region "us-east-1" \
--statement-id "3" \
--action "lambda:InvokeFunction" \
--principal s3.amazonaws.com \
--source-arn arn:aws:s3:::s3-read-weekly

#For taking input the weekly.json file following is the code:
read -p "Enter Day: " day
read -p "Enter starttime ,stoptime, cronstart, cronstop in the given sequence" starttime stoptime cronstart cronstop
string="{\"$day\":[{"\"start\"":\"$starttime\"}, {"\"stop\"":\"$stoptime\"}, {"\"cronstart\"":\"$cronstart\"},{"\"cronstop\"":\"$cronstop\"}],"
for i in {1..6}
do
read -p "Enter Day: " day
read -p "Enter starttime ,stoptime, cronstart, cronstop in the given sequence" starttime stoptime cronstart cronstop
string+="\"$day\":[{"\"start\"":\"$starttime\"}, {"\"stop\"":\"$stoptime\"}, {"\"cronstart\"":\"$cronstart\"},{"\"cronstop\"":\"$cronstop\"}],"
done
string+="}"
echo $string | sed 's/,\(.\)$/\1/' > weekly.json

aws s3 cp weekly.json s3://s3-read-weekly

#!/bin/bash

set -x

# Save the AWS account id in to a variable
aws_account_id=$(aws sts get-caller-identity --query "Account" --output text)
echo "aws account id: $aws_account_id"

# Set AWS region and bucket
aws_region="ap-south-1"
bucket_name="bojedla-s3-events"
lambda_func_name="content-upload-notif"
role_name="s3-lambda-sns"
email_address="ajayvinnu.bojedla@gmail.com"

# Create IAM role for the project
#
# Check if the role already exists else create the role
role_exists=$(aws iam get-role --role-name $role_name 2>>/dev/null)
if [ $? -eq 0 ]; then
        echo "IAM Role with the role name $role_name already exists"

        # Get role arn from the response
        role_arn=$(echo "$role_exists" | jq -r '.Role.Arn')
else
        role_response=$(aws iam create-role --role-name $role_name --assume-role-policy-document file://s3-sns-lambda.json)

        # Get role arn from the response
        role_arn=$(echo "$role_response" | jq -r '.Role.Arn')
fi

echo "$role_arn"

# Add permissions to the role
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess --role-name $role_name
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess --role-name $role_name

# Create the S3 bucket
#
#Check if the bucket name alredy exists else create the bucket
bucket_exists=$(aws s3api head-bucket --bucket $bucket_name 2>/dev/null)
if [ $? -ne 0 ]; then
        bucket_creation_output=$(aws s3api create-bucket --bucket $bucket_name --region $aws_region --create-bucket-configuration LocationConstraint=$aws_region)
else
        echo "S3 bucket with bucket name $bucket_name already exists"
fi

#Create lambda funtion Zip file
if [ -f "s3-lambda-function.zip" ]; then
        rm -rf "s3-lambda-function.zip"
fi
zip -r s3-lambda-function.zip s3-lambda-function

sleep 5

# Create a Lambda function

lambda_exists=$(aws lambda get-function --function-name $lambda_func_name 2>>/dev/null)
if [ $? -eq 0 ]; then
        echo "Lambda Function $lambda_func_name already exists"
else
        # Create a Lambda function
        aws lambda create-function \
          --region "$aws_region" \
          --function-name $lambda_func_name \
          --runtime "python3.8" \
          --handler "s3-lambda-function/s3-lambda-function.lambda_handler" \
          --memory-size 128 \
          --timeout 30 \
          --role "arn:aws:iam::$aws_account_id:role/$role_name" \
          --zip-file "fileb://s3-lambda-function.zip"

        # Add Permissions to S3 Bucket to invoke Lambda
        aws lambda add-permission \
          --function-name "$lambda_func_name" \
          --statement-id "s3-lambda-sns" \
          --action "lambda:InvokeFunction" \
          --principal s3.amazonaws.com \
          --source-arn "arn:aws:s3:::$bucket_name"
fi

# Create an S3 event trigger for the Lambda function
LambdaFunctionArn="arn:aws:lambda:$aws_region:$aws_account_id:function:content-upload-notif"
aws s3api put-bucket-notification-configuration \
  --region "$aws_region" \
  --bucket "$bucket_name" \
  --notification-configuration '{
        "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "'"$LambdaFunctionArn"'",
        "Events": ["s3:ObjectCreated:*"]
        }]
}'

# Create an SNS topic
topic_arn=$(aws sns create-topic --name s3-lambda-sns --output json | jq -r '.TopicArn')

#Trigger SNS Topic
aws sns subscribe --topic-arn "$topic_arn" --protocol email --notification-endpoint "$email_address"

#Publish SNS
aws sns publish --topic-arn "$topic_arn" --subject "A New object uploaded to S3 bucket" --message "Hello from S3. A new object is uploaded to your bucket"

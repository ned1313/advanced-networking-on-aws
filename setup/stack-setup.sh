# Have AWS CLI already install
# Have Access Key and Secret Key ready
# Recommend using us-east-1 by default
aws configure

# Create the CloudFormation stack for the basic VPC
aws cloudformation create-stack --stack-name Globomantics --template-body file://basic-network.template
# Let's first get the VPC ID

vpc_id=$(aws ec2 describe-vpcs --filters Name="tag:Name",Values="globo-primary" \
  --query 'Vpcs[0].VpcId' --output text)

# Create remote access security group

sg=$(aws ec2 create-security-group --description "allow-globo-remote" \
  --group-name "globo-remote" --vpc-id $vpc_id)

sg_id=$(echo $sg | jq .GroupId -r)

my_ip=$(curl ifconfig.me)

# Add allow RDP from your IP address

aws ec2 authorize-security-group-ingress \
    --group-id $sg_id \
    --protocol tcp \
    --port 3389 \
    --cidr $my_ip/32

# Add allow SSH from your IP address

aws ec2 authorize-security-group-ingress \
    --group-id $sg_id \
    --protocol tcp \
    --port 22 \
    --cidr $my_ip/32

# Create a web instance

aws ec2 create-key-pair --key-name GloboKey --query 'KeyMaterial' --output text > GloboKey.pem

subnet_1_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-1" \
  --query 'Subnets[0].SubnetId' --output text)

ami_id=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
  --region us-east-1 | jq .Parameters[].Value -r)

# Spin up the web-1 instance

web_1=$(aws ec2 run-instances --image-id $ami_id --count 1 \
  --instance-type t2.micro --key-name GloboKey \
  --security-group-ids $sg_id --subnet-id $subnet_1_id \
  --user-data file://webserver.txt \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=web-1},{Key=Company,Value=Globomantics}]' \
  'ResourceType=volume,Tags=[{Key=Name,Value=web-1},{Key=Company,Value=Globomantics}]')

# Create security group for ALB

sg=$(aws ec2 create-security-group --description "allow-http-anywhere" \
  --group-name "allow-http-anywhere" --vpc-id $vpc_id)

sg_id=$(echo $sg | jq .GroupId -r)

aws ec2 authorize-security-group-ingress \
    --group-id $sg_id \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0"

# Create an ALB and target group

# Create an ALB for the public subnets

public_subnets=$(aws ec2 describe-subnets --filter Name="tag:Network",Values="Public" \
  --query 'Subnets[].SubnetId' --output text)

alb=$(aws elbv2 create-load-balancer --name globo-web \
  --subnets $public_subnets \
  --security-groups $sg_id \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4)

# Create a target group for the web instances

target_group=$(aws elbv2 create-target-group --name globo-web \
  --protocol HTTP \
  --port 80 \
  --vpc-id $vpc_id \
  --target-type instance)

aws elbv2 register-targets \
  --target-group-arn $(echo $target_group | jq .TargetGroups[].TargetGroupArn -r) \
  --targets Id=$(echo $web_1 | jq .Instances[].InstanceId -r)

# Create security group for web instances and allow from ALB SG

sg=$(aws ec2 create-security-group --description "allow-http-internal" \
  --group-name "allow-http-internal" --vpc-id $vpc_id)

sg_id=$(echo $sg | jq .GroupId -r)

aws ec2 authorize-security-group-ingress \
    --group-id $sg_id \
    --protocol tcp \
    --port 80 \
    --source-group $(echo $alb | jq .LoadBalancers[0].SecurityGroups[0] -r)

# Associate web instance with security group

aws ec2 modify-instance-attribute \
  --instance-id $(echo $web_1 | jq .Instances[].InstanceId -r) \
  --groups $(echo $web_1 | jq .Instances[].NetworkInterfaces[0].Groups[].GroupId -r) $sg_id

# Create the listener for globo-web

aws elbv2 create-listener \
  --load-balancer-arn $(echo $alb | jq .LoadBalancers[].LoadBalancerArn -r) \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$(echo $target_group | jq .TargetGroups[].TargetGroupArn -r)

#################
# NACLs
#################

# Create a NACL for web subnets

web_nacl=$(aws ec2 create-network-acl --vpc-id $vpc_id)

aws ec2 create-tags --resources $(echo $web_nacl | jq .NetworkAcl.NetworkAclId -r) \
  --tags Key=Name,Value=web-acl Key=Company,Value=Globomantics

# Add rules to NACL

aws ec2 create-network-acl-entry \
  --network-acl-id $(echo $web_nacl | jq .NetworkAcl.NetworkAclId -r) \
  --ingress \
  --protocol tcp \
  --port-range From=80,To=80 \
  --cidr-block 0.0.0.0/0 \
  --rule-number 100 \
  --rule-action allow

aws ec2 create-network-acl-entry \
  --network-acl-id $(echo $web_nacl | jq .NetworkAcl.NetworkAclId -r) \
  --egress \
  --protocol -1 \
  --cidr-block 0.0.0.0/0 \
  --rule-number 100 \
  --rule-action allow

# Associate NACL with subnet-1

sub_1_assoc=$(aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=$subnet_1_id \
  --query "NetworkAcls[0].Associations[?SubnetId=='$subnet_1_id'].NetworkAclAssociationId" --output text)

aws ec2 replace-network-acl-association --association-id $sub_1_assoc \
  --network-acl-id $(echo $web_nacl | jq .NetworkAcl.NetworkAclId -r)

# Create a NACL for app subnets

app_nacl=$(aws ec2 create-network-acl --vpc-id $vpc_id)

aws ec2 create-tags --resources $(echo $app_nacl | jq .NetworkAcl.NetworkAclId -r) \
  --tags Key=Name,Value=app-acl Key=Company,Value=Globomantics

# Add rules to NACL

aws ec2 create-network-acl-entry \
  --network-acl-id $(echo $app_nacl | jq .NetworkAcl.NetworkAclId -r) \
  --ingress \
  --protocol tcp \
  --port-range From=80,To=80 \
  --cidr-block 10.0.0.0/16 \
  --rule-number 100 \
  --rule-action allow

aws ec2 create-network-acl-entry \
  --network-acl-id $(echo $app_nacl | jq .NetworkAcl.NetworkAclId -r) \
  --ingress \
  --protocol tcp \
  --port-range From=443,To=443 \
  --cidr-block 10.0.0.0/16 \
  --rule-number 150 \
  --rule-action allow

aws ec2 create-network-acl-entry \
  --network-acl-id $(echo $app_nacl | jq .NetworkAcl.NetworkAclId -r) \
  --egress \
  --protocol -1 \
  --cidr-block 0.0.0.0/0 \
  --rule-number 100 \
  --rule-action allow

# Associate NACL with subnet-4

sub_4_assoc=$(aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=$subnet_4_id \
  --query "NetworkAcls[0].Associations[?SubnetId=='$subnet_4_id'].NetworkAclAssociationId" --output text)

aws ec2 replace-network-acl-association --association-id $sub_4_assoc \
  --network-acl-id $(echo $app_nacl | jq .NetworkAcl.NetworkAclId -r)

###################
# Service Endpoints
###################

# Gateway endpoint

service_name=$(aws ec2 describe-vpc-endpoint-services --query 'ServiceNames[?ends_with(@,`s3`)]' --output text)

route_table_ids=$(aws ec2 describe-route-tables \
  --filter Name=association.subnet-id,Values=$subnet_4_id \
  --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 create-vpc-endpoint --vpc-id $vpc_id \
  --vpc-endpoint-type Gateway \
  --service-name $service_name \
  --route-table-ids $route_table_ids

# Interface endpoint

service_name=$(aws ec2 describe-vpc-endpoint-services --query 'ServiceNames[?ends_with(@,`logs`)]' --output text)

aws ec2 create-vpc-endpoint --vpc-id $vpc_id \
  --vpc-endpoint-type Interface \
  --service-name $service_name \
  --subnet-ids $subnet_1_id \
  --private-dns-enabled

##############
# Flow Logs
##############

# Create an S3 bucket

bucket_name=$(echo globo-logs-$RANDOM)

bucket=$(aws s3api create-bucket --bucket $bucket_name)

# Create a flow log for the VPC to CloudWatch

# Create a role and policy to allow 

role=$(aws iam create-role --role-name flow-log-role \
  --assume-role-policy-document file://flow-log-role.txt)

policy=$(aws iam create-policy --policy-name flow-log-policy \
  --policy-document file://flow-log-policy.txt)

aws iam attach-role-policy --role-name flow-log-role \
  --policy-arn $(echo $policy | jq .Policy.Arn -r)

aws ec2 create-flow-logs \
  --deliver-logs-permission-arn $(echo $role | jq .Role.Arn -r) \
  --log-group-name globo-vpc-logs \
  --resource-ids $vpc_id \
  --resource-type VPC \
  --traffic-type ALL

# Create a flow log for public subnets to S3 with custom log format

aws ec2 create-flow-logs \
--resource-type Subnet \
--resource-ids $public_subnets \
--traffic-type REJECT \
--log-destination-type s3 \
--log-destination "arn:aws:s3:::$bucket_name/flow_logs/" \
--log-format '${version} ${vpc-id} ${subnet-id} ${instance-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${tcp-flags} ${type} ${pkt-srcaddr} ${pkt-dstaddr}'
# You should have already deployed the basic VPC from the setup folder
# and configured your AWS CLI

# Let's first get the VPC ID

vpc_id=$(aws ec2 describe-vpcs --filters Name="tag:Name",Values="globo-primary" \
  --query 'Vpcs[0].VpcId' --output text)

# Now we're going to add another CIDR block to the VPC

aws ec2 associate-vpc-cidr-block --cidr-block "10.1.0.0/24" --vpc-id $vpc_id

# Now we'll create subnet-6 using the new CIDR block

# Get the AZ of subnet-3

az=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-3" \
  --query 'Subnets[0].AvailabilityZoneId' --output text)

# Create subnet-6 in same AZ and add the tags

subnet_6=$(aws ec2 create-subnet --availability-zone-id $az \
  --cidr-block "10.1.0.0/24" --vpc-id $vpc_id)

subnet_6_id=$(echo $subnet_6 | jq .Subnet.SubnetId -r)

aws ec2 create-tags --resources $subnet_6_id \
  --tags Key=Name,Value=subnet-6 Key=Company,Value=Globomantics Key=Network,Value=Private

# Add IPv6 to the VPC

aws ec2 associate-vpc-cidr-block --vpc-id $vpc_id --amazon-provided-ipv6-cidr-block

# Get the AWS assigned IPv6 block

ipv6_range=$(aws ec2 describe-vpcs --vpc-ids $vpc_id \
  --query 'Vpcs[0].Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlock' --output text)

# Create a /64 from the block

subnet_ipv6_range=$(sed 's|/56|/64|g' <<< $ipv6_range)

# Associate new block with subnet-6

aws ec2 associate-subnet-cidr-block --ipv6-cidr-block $subnet_ipv6_range \
  --subnet-id $subnet_6_id

# Get subnets for new instance
subnet_1_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-1" \
  --query 'Subnets[0].SubnetId' --output text)

subnet_4_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-4" \
  --query 'Subnets[0].SubnetId' --output text)

# Create a key-pair for your instances

aws ec2 create-key-pair --key-name AdvNet --query 'KeyMaterial' --output text > AdvNet.pem

# Create a security group for your instances

aws ec2 create-security-group --description "default-sg-for-AdvNet" \
  --group-name "AdvNet" --vpc-id $vpc_id

sg_id=$(aws ec2 describe-security-groups --filter Name="group-name",Values="AdvNet" \
  --query 'SecurityGroups[0].GroupId' --output text)

# Get the latest Amazon Linux 2 AMI 
# **NOTE** change the region to the one you are using

ami_id=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
  --region us-east-1 | jq .Parameters[].Value -r)

# Spin up the web-1 instance

aws ec2 run-instances --image-id $ami_id --count 1 \
  --instance-type t2.micro --key-name AdvNet \
  --security-group-ids $sg_id --subnet-id $subnet_1_id \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=web-1},{Key=Company,Value=Globomantics}]' \
  'ResourceType=volume,Tags=[{Key=Name,Value=web-1},{Key=Company,Value=Globomantics}]'

# Get the instance id and the eni id

web_1_json=$(aws ec2 describe-instances \
  --filter Name="tag:Name",Values="web-1" Name="vpc-id",Values=$vpc_id)

web_1_id=$(echo $web_1_json | jq .Reservations[0].Instances[0].InstanceId -r)

web_1_eni_1=$(echo $web_1_json | jq .Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId -r)

# Add another private IP address to web-1 on the primary ENI

aws ec2 assign-private-ip-addresses --network-interface-id $web_1_eni_1 \
  --private-ip-addresses 10.0.1.10

# Create a new ENI in subnet-4

eni_2=$(aws ec2 create-network-interface --description "web ENI" --subnet-id $subnet_4_id)

eni_2_id=$(echo $eni_2 | jq .NetworkInterface.NetworkInterfaceId -r)

# Attach new ENI to web-1

$attach_id=$(aws ec2 attach-network-interface --device-index 1 --instance-id $web_1_id \
  --network-interface-id $eni_2_id)

# Create web-2 instance

aws ec2 run-instances --image-id $ami_id --count 1 \
  --instance-type t2.micro --key-name AdvNet \
  --security-group-ids $sg_id --subnet-id $subnet_1_id \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=web-2},{Key=Company,Value=Globomantics}]' \
  'ResourceType=volume,Tags=[{Key=Name,Value=web-2},{Key=Company,Value=Globomantics}]'

# Get the instance id and the eni id

web_2_json=$(aws ec2 describe-instances \
  --filter Name="tag:Name",Values="web-2" Name="vpc-id",Values=$vpc_id)

web_2_id=$(echo $web_2_json | jq .Reservations[0].Instances[0].InstanceId -r)

# Detach the ENI from web-1

aws ec2 detach-network-interface --attachment-id $(echo $attach_id | jq .AttachmentId -r)

# Attach the ENI to web-2

aws ec2 attach-network-interface --device-index 1 --instance-id $web_2_id \
  --network-interface-id $eni_2_id
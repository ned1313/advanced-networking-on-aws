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

subnet_6=$(aws ec2 create-subnet --availability-zone-id $az --cidr-block "10.1.0.0/24" --vpc-id $vpc_id)

subnet_6_id=$(echo $subnet_6 | jq .Subnet.SubnetId -r)

aws ec2 create-tags --resources $subnet_6_id \
  --tags Key=Name,Value=subnet-6 Key=Company,Value=Globomantics Key=Network,Value=Private

# Add IPv6 to the VPC

aws ec2 associate-vpc-cidr-block --vpc-id $vpc_id --amazon-provided-ipv6-cidr-block

# Get the AWS assigned IPv6 block

ipv6_range=$(aws ec2 describe-vpcs --vpc-ids $vpc_id --query 'Vpcs[0].Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlock' --output text)

# Create a /64 from the block

subnet_ipv6_range=$(sed 's|/56|/64|g' <<< $ipv6_range)

# Associate new block with subnet-6

aws ec2 associate-subnet-cidr-block --ipv6-cidr-block $subnet_ipv6_range --subnet-id $subnet_6_id
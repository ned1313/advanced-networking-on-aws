# Let's first get the VPC ID

vpc_id=$(aws ec2 describe-vpcs --filters Name="tag:Name",Values="globo-primary" \
  --query 'Vpcs[0].VpcId' --output text)

# Get the main route table for the VPC

aws ec2 describe-route-tables --filters Name="vpc-id",Values=$vpc_id Name="association.main",Values="true" \
  --query 'RouteTables[0].Routes'

# Get the custom route table

aws ec2 describe-route-tables --filters Name="vpc-id",Values=$vpc_id Name="association.main",Values="false" \
  --query 'RouteTables[0].Routes'

# Get subnets associated with custom route table

subnets=$(aws ec2 describe-route-tables --filters Name="vpc-id",Values=$vpc_id Name="association.main",Values="false" \
  --query 'RouteTables[0].Associations[].SubnetId' --output text)

aws ec2 describe-subnets --subnet-ids $subnets --query 'Subnets[].Tags[?Key==`Name`].Value[]'

# Let's create NAT gateways for the  private subnets

# Allocate an EIP

eip=$(aws ec2 allocate-address --domain vpc)

eip_alloc=$(echo $eip | jq .AllocationId -r)

# Get the subnet ID for the subnet-1

subnet_1_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-1" \
  --query 'Subnets[0].SubnetId' --output text)

# Create a NAT gateway in subnet-1

nat_gw=$(aws ec2 create-nat-gateway --allocation-id $eip_alloc --subnet-id $subnet_1_id)

nat_gw_id=$(echo $nat_gw | jq .NatGateway.NatGatewayId -r)

# Create a route table for subnet-4

rt1=$(aws ec2 create-route-table --vpc-id $vpc_id)

rt1_id=$(echo $rt1 | jq .RouteTable.RouteTableId -r)

# Add entries to the route table

aws ec2 create-route --destination-cidr-block "0.0.0.0/0" --nat-gateway-id $nat_gw_id --route-table-id $rt1_id

# Get the subnet ID for the subnet-4

subnet_4_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-4" \
  --query 'Subnets[0].SubnetId' --output text)

# Associate route table with each subnet-4

aws ec2 associate-route-table --route-table-id $rt1_id --subnet-id $subnet_4_id

# Rinse and repeat for each AZ

# Allocate an EIP

eip2=$(aws ec2 allocate-address --domain vpc)

eip_alloc_2=$(echo $eip2 | jq .AllocationId -r)

# Get the subnet ID for the subnet-2

subnet_2_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-2" \
  --query 'Subnets[0].SubnetId' --output text)

# Create a NAT gateway in subnet-2

nat_gw_2=$(aws ec2 create-nat-gateway --allocation-id $eip_alloc_2 --subnet-id $subnet_2_id)

nat_gw_id_2=$(echo $nat_gw_2 | jq .NatGateway.NatGatewayId -r)

# Create a route table for subnet-5

rt2=$(aws ec2 create-route-table --vpc-id $vpc_id)

rt2_id=$(echo $rt2 | jq .RouteTable.RouteTableId -r)

# Add entries to the route table

aws ec2 create-route --destination-cidr-block "0.0.0.0/0" --nat-gateway-id $nat_gw_id_2 --route-table-id $rt2_id

# Get the subnet ID for the subnet-5

subnet_5_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-5" \
  --query 'Subnets[0].SubnetId' --output text)

# Associate route table with each subnet-5

aws ec2 associate-route-table --route-table-id $rt2_id --subnet-id $subnet_5_id

# Get Windows AMI for Server 2016

ami_id=$(aws ssm get-parameters --names /aws/service/ami-windows-latest/Windows_Server-2016-English-Full-Base \
   | jq .Parameters[].Value -r)

# Create a key-pair for your instances

aws ec2 create-key-pair --key-name GloboKey --query 'KeyMaterial' --output text > GloboKey.pem

# Create a security group for your jump box

aws ec2 create-security-group --description "allow-rdp-remote" \
  --group-name "RDPRemote" --vpc-id $vpc_id

sg_id=$(aws ec2 describe-security-groups --filter Name="group-name",Values="RDPRemote" \
  --query 'SecurityGroups[0].GroupId' --output text)

my_ip=$(curl ifconfig.me)

# Add allow RDP from your IP address

aws ec2 authorize-security-group-ingress \
    --group-id $sg_id \
    --protocol tcp \
    --port 3389 \
    --cidr $my_ip/32

# Create the jump box

aws ec2 run-instances --image-id $ami_id --count 1 \
  --instance-type t2.large --key-name GloboKey \
  --security-group-ids $sg_id --subnet-id $subnet_1_id \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=jump},{Key=Company,Value=Globomantics}]' \
  'ResourceType=volume,Tags=[{Key=Name,Value=web-1},{Key=Company,Value=Globomantics}]'

# Create an Elastic IP

# Create a security group for your private instances

aws ec2 create-security-group --description "allow-rdp-internal" \
  --group-name "RDPInternal" --vpc-id $vpc_id

sg_id=$(aws ec2 describe-security-groups --filter Name="group-name",Values="RDPInternal" \
  --query 'SecurityGroups[0].GroupId' --output text)

# Allow RDP from the VPC

aws ec2 authorize-security-group-ingress \
    --group-id $sg_id \
    --protocol tcp \
    --port 3389 \
    --cidr "10.0.0.0/16"

# Spin up two domain controller instances

aws ec2 run-instances --image-id $ami_id --count 1 \
  --instance-type t2.large --key-name GloboKey \
  --security-group-ids $sg_id --subnet-id $subnet_4_id \
  --private-ip-address "10.0.4.10" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=dc-1},{Key=Company,Value=Globomantics}]' \
  'ResourceType=volume,Tags=[{Key=Name,Value=web-1},{Key=Company,Value=Globomantics}]'

aws ec2 run-instances --image-id $ami_id --count 1 \
  --instance-type t2.large --key-name GloboKey \
  --security-group-ids $sg_id --subnet-id $subnet_5_id \
  --private-ip-address "10.0.5.10" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=dc-2},{Key=Company,Value=Globomantics}]' \
  'ResourceType=volume,Tags=[{Key=Name,Value=web-1},{Key=Company,Value=Globomantics}]'

# Create Domain Controller SG

aws ec2 create-security-group --description "Domain Controllers" \
  --group-name "DomainControllerSG" --vpc-id $vpc_id

dc_sg_id=$(aws ec2 describe-security-groups --filter Name="group-name",Values="DomainControllerSG" \
  --query 'SecurityGroups[0].GroupId' --output text)

# Create Domain Members SG

aws ec2 create-security-group --description "Domain Members" \
  --group-name "DomainMembersG" --vpc-id $vpc_id

dm_sg_id=$(aws ec2 describe-security-groups --filter Name="group-name",Values="DomainMembersSG" \
  --query 'SecurityGroups[0].GroupId' --output text)

# Populate the DC and DM SGs with a LOT of SG rules, like so so so many

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 53 \
    --cidr "10.0.0.0/16"

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 53 \
    --cidr "10.0.0.0/16"

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 80 \
    --cidr "10.0.0.0/16"

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 5985 \
    --cidr "10.0.0.0/16"

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol all \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 67 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 88 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 123 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 138 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 137 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 389 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 445 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 464 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 2535 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 5355 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol udp \
    --port 49152-65535 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol icmp \
    --port -1 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 88 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 135 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 139 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 389 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 445 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 464 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 636 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 3268-3269 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 5722 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 9389 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dc_sg_id \
    --protocol tcp \
    --port 49152-65535 \
    --source-group $dm_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol udp \
    --port 88 \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol udp \
    --port 389 \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol udp \
    --port 445 \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol udp \
    --port 49152-65535 \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol tcp \
    --port 88 \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol tcp \
    --port 389 \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol tcp \
    --port 445 \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol tcp \
    --port 636 \
    --source-group $dc_sg_id

aws ec2 authorize-security-group-ingress \
    --group-id $dm_sg_id \
    --protocol tcp \
    --port 49152-65535 \
    --source-group $dc_sg_id
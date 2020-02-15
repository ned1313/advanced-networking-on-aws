###################
# Setup
###################

# Create the VPCs using CloudFormation
aws cloudformation create-stack --stack-name Peering-Example --template-body file://three-vpcs.template

###################
# VPC Peering
###################

# Get the VPC IDs for each VPC
vpc1_id=$(aws ec2 describe-vpcs --filters Name="tag:Name",Values="globo-vpc1" \
  --query 'Vpcs[0].VpcId' --output text)

vpc2_id=$(aws ec2 describe-vpcs --filters Name="tag:Name",Values="globo-vpc2" \
  --query 'Vpcs[0].VpcId' --output text)

vpc3_id=$(aws ec2 describe-vpcs --filters Name="tag:Name",Values="globo-vpc3" \
  --query 'Vpcs[0].VpcId' --output text)

# Create the peering request
peer_req=$(aws ec2 create-vpc-peering-connection --vpc-id $vpc1_id --peer-vpc-id $vpc3_id)

aws ec2 create-tags \
  --resources $(echo $peer_req | jq .VpcPeeringConnection.VpcPeeringConnectionId -r) \
  --tags Key=Name,Value=vpc1-vpc3 Key=Company,Value=Globomantics

# Accept the peering request
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $(echo $peer_req | jq .VpcPeeringConnection.VpcPeeringConnectionId -r)

# Get route tables for vpc1

vpc1_rt_ids=$(aws ec2 describe-route-tables \
  --filter Name=vpc-id,Values=$vpc1_id \
  --query 'RouteTables[].RouteTableId' --output json)

# Get route tables for vpc3

vpc3_rt_ids=$(aws ec2 describe-route-tables \
  --filter Name=vpc-id,Values=$vpc3_id \
  --query 'RouteTables[].RouteTableId' --output json)

# Add route to vpc1 for vpc3 destinations

for OUTPUT in $(echo $vpc1_rt_ids | jq .[] -r)
do
  aws ec2 create-route --route-table-id $OUTPUT \
    --destination-cidr-block "10.2.0.0/16" \
    --vpc-peering-connection-id $(echo $peer_req | jq .VpcPeeringConnection.VpcPeeringConnectionId -r)
done

# Add route to vpc3 for vpc1 destinations

for OUTPUT in $(echo $vpc3_rt_ids | jq .[] -r)
do
  aws ec2 create-route --route-table-id $OUTPUT \
    --destination-cidr-block "10.0.0.0/16" \
    --vpc-peering-connection-id $(echo $peer_req | jq .VpcPeeringConnection.VpcPeeringConnectionId -r)
done

################
# VPC VPN
################

# Create the Destination VPC using CloudFormation
aws cloudformation create-stack --stack-name VPN-Example --template-body file://vpn-vpc.template

# Get the two VPC IDs

dc_id=$(aws ec2 describe-vpcs --filters Name="tag:Name",Values="globo-dc" \
  --query 'Vpcs[0].VpcId' --output text)

vpc_id=$(aws ec2 describe-vpcs --filters Name="tag:Name",Values="globo-vpc1" \
  --query 'Vpcs[0].VpcId' --output text)

# Create a VGW

vgw=$(aws ec2 create-vpn-gateway --type ipsec.1)

# Attach the VGW to the VPC

aws ec2 attach-vpn-gateway --vpc-id $vpc_id \
  --vpn-gateway-id $(echo $vgw | jq .VpnGateway.VpnGatewayId -r)

# Spin up a Server 2012 instance for VPN connection

# Get the subnet for the server deployment

vpn_subnet_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-1" \
  Name=vpc-id,Values=$dc_id \
  --query 'Subnets[0].SubnetId' --output text)

# Create remote access security group

sg=$(aws ec2 create-security-group --description "vpn-server-sg" \
  --group-name "vpn-server-sg" --vpc-id $dc_id)

sg_id=$(echo $sg | jq .GroupId -r)

my_ip=$(curl ifconfig.me)

# Add allow RDP from your IP address

aws ec2 authorize-security-group-ingress \
    --group-id $sg_id \
    --protocol tcp \
    --port 3389 \
    --cidr $my_ip/32

# Allow UDP 4500 from anywhere for VPN

aws ec2 authorize-security-group-ingress \
    --group-id $sg_id \
    --protocol udp \
    --port 4500 \
    --cidr 0.0.0.0/0

aws ec2 create-key-pair --key-name VPNKey --query 'KeyMaterial' --output text > VPNKey.pem

ami_id=$(aws ssm get-parameters --names /aws/service/ami-windows-latest/Windows_Server-2012-R2_RTM-English-64Bit-Base \
  --region us-east-1 | jq .Parameters[].Value -r)

inst=$(aws ec2 run-instances --image-id $ami_id --count 1 \
  --instance-type t2.large --key-name VPNKey \
  --security-group-ids $sg_id --subnet-id $vpn_subnet_id \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=vpn},{Key=Company,Value=Globomantics}]' \
  'ResourceType=volume,Tags=[{Key=Name,Value=vpn},{Key=Company,Value=Globomantics}]')

  # Allocate an EIP

eip=$(aws ec2 allocate-address --domain vpc)

aws ec2 associate-address \
  --instance-id $(echo $inst | jq .Instances[0].InstanceId -r) \
  --allocation-id $(echo $eip | jq .AllocationId -r)

# Edit the source/dest check on the ENI

aws ec2 modify-network-interface-attribute \
  --network-interface-id $(echo $inst | jq .Instances[0].NetworkInterfaces[0].NetworkInterfaceId -r) \
  --no-source-dest-check

# Create a customer gateway

cgw=$(aws ec2 create-customer-gateway \
  --public-ip $(echo $eip | jq .PublicIp -r) \
  --type ipsec.1 \
  --device-name globo-dc-cgw \
  --bgp-asn 65000)

vpn_conn=$(aws ec2 create-vpn-connection \
  --customer-gateway-id $(echo $cgw | jq .CustomerGateway.CustomerGatewayId -r) \
  --vpn-gateway-id $(echo $vgw | jq .VpnGateway.VpnGatewayId -r) \
  --type ipsec.1 \
  --options "{\"StaticRoutesOnly\":true}")

echo $vpn_conn | jq .VpnConnection.CustomerGatewayConfiguration -r > vpn_config.xml

aws ec2 create-vpn-connection-route \
  --vpn-connection-id $(echo $vpn_conn | jq .VpnConnection.VpnConnectionId -r) \
  --destination-cidr-block 192.168.0.0/16

# Create a route for the globo DC for each route table

vpc_rt_ids=$(aws ec2 describe-route-tables \
  --filter Name=vpc-id,Values=$vpc_id \
  --query 'RouteTables[].RouteTableId' --output json)

for OUTPUT in $(echo $vpc_rt_ids | jq .[] -r)
do
  aws ec2 create-route --route-table-id $OUTPUT \
    --destination-cidr-block "192.168.0.0/16" \
    --gateway-id $(echo $vgw | jq .VpnGateway.VpnGatewayId -r)
done

# Create an EC2 instance in vpc1 to ping

ping_sg=$(aws ec2 create-security-group --description "vpn-client-sg" \
  --group-name "vpn-client-sg" --vpc-id $vpc_id)

ping_sg_id=$(echo $sg | jq .GroupId -r)

# Allow any traffic from Globo DC

aws ec2 authorize-security-group-ingress \
    --group-id $ping_sg_id \
    --protocol all \
    --cidr 192.168.0.0/16

# Get the subnet from Globo VPC

ping_subnet_id=$(aws ec2 describe-subnets --filter Name="tag:Name",Values="subnet-1" \
  Name=vpc-id,Values=$vpc_id \
  --query 'Subnets[0].SubnetId' --output text)

ping_inst=$(aws ec2 run-instances --image-id $ami_id --count 1 \
  --instance-type t2.medium --key-name VPNKey \
  --security-group-ids $ping_sg_id --subnet-id $ping_subnet_id \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=vpn-client},{Key=Company,Value=Globomantics}]' \
  'ResourceType=volume,Tags=[{Key=Name,Value=vpn-client},{Key=Company,Value=Globomantics}]')

echo $ping_inst | jq .Instances[].PrivateIpAddress -r
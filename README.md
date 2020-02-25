# Advanced Networking on AWS

Welcome to Advanced Networking on AWS. These exercise files are meant to accompany my course on Pluralsight.

## Using the files

Each folder follows the progression of modules through the course. The setup folder contains a CloudFormation template, which will deploy a simple VPC. It assumes that the region you choose has at least three Availability Zones. I used `us-east-1` for all of my examples, but choose the region that works best for you.

The rest of the modules (except module 6) build off the initial VPC, creating additional subnets, CIDR ranges, routes, and security groups. In the script for module 4, there is a process that spins up three Server 2016 boxes. Two are meant to function as domain controllers, and the third is a jump box in a public subnet. The actual configuration of the domain controllers is left as an exercise to you. There's nothing special about the domain, you can simply choose a name and configure custom DNS in the DHCP options set.

Module 6 has two CloudFormation templates that are used to demonstrate VPC peering and site-to-site VPNs. They are meant to be used separately from the simple VPC you deployed earlier. You may hit the limit of 5 VPCs per region if you have everything deployed at the same time. You can simply log a support request for the limit to be bumped up to 10, and AWS should resolve it quickly.

## Course prerequisites

There are a few pieces of prerequisite software you should have available

* **Code Editor** - Have a code editor of some kind. My preference is VS Code, but you do you.
* **AWS CLI** - The exercise files all assume you have the AWS CLI installed. You won't get very far without it.
* **jq** - In most cases I tried to use the built-in `query` function of the AWS CLI, but sometimes it just didn't work out.

You might be able to run these exercises in a PowerShell terminal, but it won't be easy. I recommend installing Windows Subsystem for Linux if you are on a Windows box. Linux and Mac users should have no problems.

## MONEY!!!

A gentle reminder about cost. The course will have you creating resources in AWS. Some of the resources are not going to be 100% free. I have tried to use free resources when possible, but EC2 instances, elastic IPs, and NAT gateways all cost money. We're probably talking a few dollars for the duration of the exercises, but it won't be zero.

## Conclusion

I hope you enjoy taking this course as much as I did creating it. I'd love to hear feedback and suggestions for revisions. Log an issue on this repo or hit me up on Twitter.

Thanks and happy automating!

Ned
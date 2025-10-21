terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  alias  = "singapore"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "tokyo"
  region = "ap-northeast-1"
}

# VPCs (simplified: one public subnet each)
module "singapore_vpc" {
  source   = "../terraform/modules/vpc"
  providers = { aws = aws.singapore }

  region_name       = "singapore"
  vpc_cidr          = "10.0.0.0/16"
  subnet_cidr       = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"
  create_default_igw_route = false # steer 0/0 to TGW
}

module "tokyo_vpc" {
  source   = "../terraform/modules/vpc"
  providers = { aws = aws.tokyo }

  region_name       = "tokyo"
  vpc_cidr          = "10.1.0.0/16"
  subnet_cidr       = "10.1.1.0/24"
  availability_zone = "ap-northeast-1a"
}

# TGWs
resource "aws_ec2_transit_gateway" "sg" {
  provider = aws.singapore
  description = "SG TGW"
}

resource "aws_ec2_transit_gateway" "tokyo" {
  provider = aws.tokyo
  description = "Tokyo TGW"
}

# TGW peering
resource "aws_ec2_transit_gateway_peering_attachment" "sg_tokyo" {
  provider = aws.singapore
  transit_gateway_id = aws_ec2_transit_gateway.sg.id
  peer_region        = "ap-northeast-1"
  peer_transit_gateway_id = aws_ec2_transit_gateway.tokyo.id
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "tokyo_accept" {
  provider = aws.tokyo
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.sg_tokyo.id
}

# Attach VPCs to TGWs
resource "aws_ec2_transit_gateway_vpc_attachment" "sg_attach" {
  provider           = aws.singapore
  subnet_ids         = [module.singapore_vpc.subnet_id]
  transit_gateway_id = aws_ec2_transit_gateway.sg.id
  vpc_id             = module.singapore_vpc.vpc_id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tokyo_attach" {
  provider           = aws.tokyo
  subnet_ids         = [module.tokyo_vpc.subnet_id]
  transit_gateway_id = aws_ec2_transit_gateway.tokyo.id
  vpc_id             = module.tokyo_vpc.vpc_id
}

# Route Singapore 0/0 to TGW
resource "aws_route" "sg_to_tgw" {
  provider               = aws.singapore
  route_table_id         = module.singapore_vpc.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.sg.id
}

# Allocate Tokyo NATGW EIP
resource "aws_eip" "tokyo_nat" {
  provider = aws.tokyo
  domain   = "vpc"
}

resource "aws_nat_gateway" "tokyo" {
  provider      = aws.tokyo
  allocation_id = aws_eip.tokyo_nat.id
  subnet_id     = module.tokyo_vpc.subnet_id
}

# Route Tokyo VPC 0/0 to IGW for NATGW to egress
# Note: module already has IGW default route

# Outputs
output "tokyo_nat_eip" {
  value = aws_eip.tokyo_nat.public_ip
}

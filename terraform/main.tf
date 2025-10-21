terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

# Singapore Region Provider
provider "aws" {
  alias  = "singapore"
  region = "ap-southeast-1"
}

# Tokyo Region Provider
provider "aws" {
  alias  = "tokyo"
  region = "ap-northeast-1"
}

# Manage SSH key pair in Singapore region with local public key
resource "aws_key_pair" "singapore" {
  provider   = aws.singapore
  key_name   = "hft-benchmark-managed"
  public_key = file("~/.ssh/hft-benchmark.pub")

  tags = {
    Project = "hft-benchmark"
    Region  = "singapore"
  }
}

# Manage SSH key pair in Tokyo region with the same local public key
resource "aws_key_pair" "tokyo" {
  provider   = aws.tokyo
  key_name   = "hft-benchmark-managed"
  public_key = file("~/.ssh/hft-benchmark.pub")

  tags = {
    Project = "hft-benchmark"
    Region  = "tokyo"
  }
}

# Singapore VPC and EC2
module "singapore_vpc" {
  source   = "./modules/vpc"
  providers = {
    aws = aws.singapore
  }

  region_name      = "singapore"
  vpc_cidr         = "10.0.0.0/16"
  subnet_cidr      = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"
  create_default_igw_route = false  # Private SG subnet; no IGW route

  tags = {
    Project = "hft-benchmark"
    Region  = "singapore"
  }
}

module "singapore_ec2" {
  source   = "./modules/ec2"
  providers = {
    aws = aws.singapore
  }

  instance_name       = "singapore-client"
  instance_type       = "t3.small"
  subnet_id           = module.singapore_vpc.subnet_id
  security_group_id   = module.singapore_vpc.security_group_id
  # Use Terraform-managed key pair
  key_name            = aws_key_pair.singapore.key_name
  user_data           = templatefile("${path.module}/user-data/ipip_client.sh.tmpl", {
    server_private_ip  = module.tokyo_bastion.private_ip
  })
  
  source_dest_check   = true
  associate_public_ip = false  # No public IP - access through bastion only
  # No IAM profile needed for netcat-based exchange

  # Ensure EC2 is created after key pair and destroyed BEFORE VPC
  depends_on = [module.singapore_vpc, aws_key_pair.singapore]

  tags = {
    Project = "hft-benchmark"
    Role    = "client"
    Region  = "singapore"
  }
}

# Tokyo VPC and NAT Gateway
module "tokyo_vpc" {
  source   = "./modules/vpc"
  providers = {
    aws = aws.tokyo
  }

  region_name      = "tokyo"
  vpc_cidr         = "10.1.0.0/16"
  subnet_cidr      = "10.1.1.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Project = "hft-benchmark"
    Region  = "tokyo"
  }
}

# Allocate Elastic IP for Tokyo NAT Gateway
resource "aws_eip" "tokyo_nat" {
  provider = aws.tokyo
  domain   = "vpc"
  depends_on = [module.tokyo_vpc.internet_gateway_id]

  tags = {
    Name    = "tokyo-nat-eip"
    Project = "hft-benchmark"
  }
}

# Create NAT Gateway in Tokyo
resource "aws_nat_gateway" "tokyo" {
  provider      = aws.tokyo
  allocation_id = aws_eip.tokyo_nat.id
  subnet_id     = module.tokyo_vpc.subnet_id

  depends_on = [module.tokyo_vpc.internet_gateway_id]

  tags = {
    Name    = "tokyo-nat-gateway"
    Project = "hft-benchmark"
  }
}

# Bastion Host in Tokyo for SSH access to Singapore
module "tokyo_bastion" {
  source   = "./modules/ec2"
  providers = {
    aws = aws.tokyo
  }

  instance_name       = "tokyo-bastion"
  instance_type       = "t3.micro"
  subnet_id           = module.tokyo_vpc.subnet_id
  security_group_id   = module.tokyo_vpc.security_group_id
  # Use Terraform-managed key pair
  key_name            = aws_key_pair.tokyo.key_name
  user_data           = templatefile("${path.module}/user-data/ipip_server.sh.tmpl", {})
  
  source_dest_check   = false
  associate_public_ip = true
  # No IAM profile needed with netcat-based exchange

  depends_on = [module.tokyo_vpc, aws_key_pair.tokyo]

  tags = {
    Project = "hft-benchmark"
    Role    = "bastion"
    Region  = "tokyo"
  }
}

# Stable egress IP for Tokyo WireGuard NAT (bastion)
resource "aws_eip" "tokyo_bastion" {
  provider = aws.tokyo
  domain   = "vpc"
  instance = module.tokyo_bastion.instance_id

  tags = {
    Name    = "tokyo-bastion-eip"
    Project = "hft-benchmark"
  }
}

# VPC Peering
module "peering" {
  source = "./modules/peering"
  
  providers = {
    aws.singapore = aws.singapore
    aws.tokyo     = aws.tokyo
  }

  singapore_vpc_id         = module.singapore_vpc.vpc_id
  tokyo_vpc_id             = module.tokyo_vpc.vpc_id
  singapore_route_table_id = module.singapore_vpc.route_table_id
  tokyo_route_table_id     = module.tokyo_vpc.route_table_id
  create_default_route_via_peering = false

  # Ensure peering is destroyed BEFORE VPCs to prevent VPC deletion conflicts
  depends_on = [module.singapore_vpc, module.tokyo_vpc]

  tags = {
    Project = "hft-benchmark"
  }
}

# Outputs
output "singapore_instance_public_ip" {
  value       = module.singapore_ec2.public_ip
  description = "Public IP of Singapore EC2 instance"
}

output "singapore_instance_private_ip" {
  value       = module.singapore_ec2.private_ip
  description = "Private IP of Singapore EC2 instance"
}


output "tokyo_nat_gateway_id" {
  value       = aws_nat_gateway.tokyo.id
  description = "Tokyo NAT Gateway ID"
}

output "tokyo_nat_elastic_ip" {
  value       = aws_eip.tokyo_nat.public_ip
  description = "Elastic IP for Tokyo NAT Gateway (egress IP)"
}

output "peering_connection_id" {
  value       = module.peering.peering_connection_id
  description = "VPC Peering Connection ID"
}

output "singapore_security_group_id" {
  value       = module.singapore_vpc.security_group_id
  description = "Singapore VPC Security Group ID"
}

output "tokyo_security_group_id" {
  value       = module.tokyo_vpc.security_group_id
  description = "Tokyo VPC Security Group ID"
}

output "tokyo_bastion_public_ip" {
  value       = try(module.tokyo_bastion.public_ip, null)
  description = "Public IP of Tokyo bastion (SSH entrypoint and HTTP proxy)"
}

output "tokyo_bastion_private_ip" {
  value       = try(module.tokyo_bastion.private_ip, null)
  description = "Private IP of Tokyo bastion"
}

output "tokyo_bastion_egress_ip" {
  value       = try(aws_eip.tokyo_bastion.public_ip, null)
  description = "Elastic IP used for egress from Tokyo WireGuard NAT"
}

output "active_keypair_names" {
  value = {
    singapore = aws_key_pair.singapore.key_name
    tokyo     = aws_key_pair.tokyo.key_name
  }
  description = "Active EC2 key pair names per region"
}

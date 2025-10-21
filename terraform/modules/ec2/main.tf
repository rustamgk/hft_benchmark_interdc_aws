terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# EC2 Module - Creates an EC2 instance in a VPC

# Get the latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance
resource "aws_instance" "main" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  source_dest_check      = var.source_dest_check
  associate_public_ip_address = var.associate_public_ip
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  
  user_data = var.user_data
  user_data_replace_on_change = true

  tags = merge(
    var.tags,
    {
      Name = var.instance_name
    }
  )
}

# Outputs
output "instance_id" {
  value       = aws_instance.main.id
  description = "Instance ID"
}

output "public_ip" {
  value       = aws_instance.main.public_ip
  description = "Public IP address"
}

output "private_ip" {
  value       = aws_instance.main.private_ip
  description = "Private IP address"
}

output "primary_network_interface_id" {
  value       = aws_instance.main.primary_network_interface_id
  description = "Primary ENI (Elastic Network Interface) ID"
}

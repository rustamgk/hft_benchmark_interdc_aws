terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      configuration_aliases = [
        aws.singapore,
        aws.tokyo,
      ]
    }
  }
}

# Peering Module - Creates VPC peering connection between regions

# VPC Peering Connection (initiated from Singapore)
resource "aws_vpc_peering_connection" "singapore_to_tokyo" {
  provider      = aws.singapore
  vpc_id        = var.singapore_vpc_id
  peer_vpc_id   = var.tokyo_vpc_id
  peer_region   = "ap-northeast-1"
  auto_accept   = false

  tags = merge(
    var.tags,
    {
      Name = "sg-to-tokyo-peering"
    }
  )
}

# Accept the peering connection from Tokyo side
resource "aws_vpc_peering_connection_accepter" "tokyo" {
  provider                  = aws.tokyo
  vpc_peering_connection_id = aws_vpc_peering_connection.singapore_to_tokyo.id
  auto_accept               = true

  tags = merge(
    var.tags,
    {
      Name = "sg-to-tokyo-peering-accepted"
    }
  )
}

# Enable DNS resolution for peering
resource "aws_vpc_peering_connection_options" "singapore" {
  provider                  = aws.singapore
  vpc_peering_connection_id = aws_vpc_peering_connection.singapore_to_tokyo.id

  # Wait for accepter to be active first
  depends_on = [aws_vpc_peering_connection_accepter.tokyo]

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_vpc_peering_connection_options" "tokyo" {
  provider                  = aws.tokyo
  vpc_peering_connection_id = aws_vpc_peering_connection.singapore_to_tokyo.id

  # Wait for accepter to be active first
  depends_on = [aws_vpc_peering_connection_accepter.tokyo]

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

# Route from Singapore to Tokyo VPC via peering connection
resource "aws_route" "singapore_to_tokyo_vpc" {
  provider                   = aws.singapore
  route_table_id             = var.singapore_route_table_id
  destination_cidr_block     = "10.1.0.0/16"
  vpc_peering_connection_id  = aws_vpc_peering_connection.singapore_to_tokyo.id

  depends_on = [aws_vpc_peering_connection_accepter.tokyo]
}

# Route all internet traffic from Singapore through Tokyo via peering
# This ensures traffic gets SNAT'd with Tokyo's Elastic IP
resource "aws_route" "singapore_internet_via_tokyo" {
  count                     = var.create_default_route_via_peering ? 1 : 0
  provider                  = aws.singapore
  route_table_id            = var.singapore_route_table_id
  destination_cidr_block    = "0.0.0.0/0"
  vpc_peering_connection_id = aws_vpc_peering_connection.singapore_to_tokyo.id

  depends_on = [aws_vpc_peering_connection_accepter.tokyo]
}

# Route from Tokyo to Singapore VPC via peering connection
resource "aws_route" "tokyo_to_singapore_vpc" {
  provider                   = aws.tokyo
  route_table_id             = var.tokyo_route_table_id
  destination_cidr_block     = "10.0.0.0/16"
  vpc_peering_connection_id  = aws_vpc_peering_connection.singapore_to_tokyo.id

  depends_on = [aws_vpc_peering_connection_accepter.tokyo]
}

# Outputs
output "peering_connection_id" {
  value       = aws_vpc_peering_connection.singapore_to_tokyo.id
  description = "VPC Peering Connection ID"
}

output "peering_connection_status" {
  value       = aws_vpc_peering_connection_accepter.tokyo.vpc_peering_connection_id
  description = "VPC Peering Connection Status"
}

# Variables for VPC module

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet"
}

variable "availability_zone" {
  type        = string
  description = "Availability zone for resources"
}

variable "region_name" {
  type        = string
  description = "Name of the region (for naming)"
}

variable "create_default_igw_route" {
  type        = bool
  description = "Create default 0.0.0.0/0 route to IGW (set to false if peering will manage routing)"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}

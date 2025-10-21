variable "create_default_route_via_peering" {
  description = "Whether to create a 0.0.0.0/0 route in Singapore via the peering connection"
  type        = bool
  default     = false
}
# Variables for Peering module

variable "singapore_vpc_id" {
  type        = string
  description = "VPC ID of Singapore region"
}

variable "tokyo_vpc_id" {
  type        = string
  description = "VPC ID of Tokyo region"
}

variable "singapore_route_table_id" {
  type        = string
  description = "Route table ID for Singapore"
}

variable "tokyo_route_table_id" {
  type        = string
  description = "Route table ID for Tokyo"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to peering resources"
  default     = {}
}

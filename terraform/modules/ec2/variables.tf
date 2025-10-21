# Variables for EC2 module

variable "instance_name" {
  type        = string
  description = "Name of the EC2 instance"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.small"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID where instance will be launched"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID"
}

variable "key_name" {
  type        = string
  description = "Name of the SSH key pair"
}

variable "source_dest_check" {
  type        = bool
  description = "Whether to enable source destination check"
  default     = true
}

variable "associate_public_ip" {
  type        = bool
  description = "Whether to associate a public IP"
  default     = true
}

variable "user_data" {
  type        = string
  description = "User data script to run on instance startup"
  default     = ""
}

variable "iam_instance_profile" {
  type        = string
  description = "Optional IAM instance profile name to attach"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the instance"
  default     = {}
}

variable "ami_id" {
  type        = string
  description = "Override AMI ID. If empty, the latest Ubuntu 22.04 LTS AMI will be used."
  default     = ""
}

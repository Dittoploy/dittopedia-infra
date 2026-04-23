variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "dittopedia-frontend-staging"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "dittopedia-staging-key"
}

variable "public_key" {
  description = "SSH public key for EC2"
  type        = string
}

variable "private_key" {
  description = "SSH private key for provisioner (if used)"
  type        = string
  sensitive   = true
}

variable "ssh_ingress_cidr" {
  description = "CIDR block for SSH access"
  type        = string
}

variable "frontend_port" {
  description = "Port for frontend app"
  type        = number
  default     = 80
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "dittopedia"
    Environment = "staging"
    ManagedBy   = "Terraform"
  }
}
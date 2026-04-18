variable "aws_region" {
  description = "AWS region for backend deployment"
  type        = string
  default     = "eu-west-3"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "dittopedia-backend-staging"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "ssh_ingress_cidr" {
  description = "CIDR block for SSH access (Jenkins worker IP). Must not be 0.0.0.0/0"
  type        = string
  validation {
    condition     = var.ssh_ingress_cidr != "0.0.0.0/0"
    error_message = "SSH CIDR must not be 0.0.0.0/0 for security reasons."
  }
}

variable "backend_port" {
  description = "Backend application port"
  type        = number
  default     = 3000
}

variable "valkey_port" {
  description = "Valkey cache port (internal only)"
  type        = number
  default     = 6379
}

variable "enable_rds" {
  description = "Enable RDS PostgreSQL (if not available, set to false for EC2 fallback)"
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "RDS instance type (free tier: db.t3.micro)"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS storage in GB (free tier: 20)"
  type        = number
  default     = 20
}

variable "rds_backup_retention_period" {
  description = "RDS backup retention in days. Free tier accounts may require 0."
  type        = number
  default     = 0
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}

variable "rds_database_name" {
  description = "Initial database name"
  type        = string
  default     = "dittopedia"
}

variable "rds_master_username" {
  description = "RDS master username"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "rds_master_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "public_key" {
  description = "SSH public key for EC2 key pair"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
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

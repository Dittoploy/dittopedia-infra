variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "eu-west-3"
}

variable "instance_name" {
  type        = string
  description = "EC2 instance name tag"
  default     = "dittopedia-docs-staging"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.small"
}

variable "key_name" {
  type        = string
  description = "AWS key pair name"
}

variable "public_key" {
  type        = string
  description = "Public SSH key used to create key pair when needed"
  default     = ""
}

variable "ssh_ingress_cidr" {
  type        = string
  description = "Trusted CIDR allowed to SSH to docs instance (set explicitly; e.g., your IP or VPN range for security)"
}

variable "docs_port" {
  type        = number
  description = "Public port exposed by docs app"
  default     = 80
}

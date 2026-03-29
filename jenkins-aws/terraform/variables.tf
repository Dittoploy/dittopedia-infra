variable "project_name" {
	description = "Nom du projet pour préfixer les ressources (ex: dittopedia)"
	type        = string
}
variable "key_name" {
	description = "Nom de la key pair EC2 à utiliser pour SSH"
	type        = string
}
# variables.tf
# Variables for Jenkins AWS infrastructure

variable "aws_region" {
	description = "AWS region to deploy resources"
	type        = string
	default     = "eu-west-3"
}

variable "vpc_cidr" {
	description = "CIDR block for the VPC"
	type        = string
	default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
	description = "CIDR block for the public subnet"
	type        = string
	default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
	description = "CIDR block for the private subnet"
	type        = string
	default     = "10.0.2.0/24"
}

variable "az" {
	description = "Availability Zone for subnets"
	type        = string
	default     = "eu-west-3a"
}

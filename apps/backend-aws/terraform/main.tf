terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ====================================
# Data Sources: Query AWS for defaults
# ====================================

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get available subnets in default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get most recent Ubuntu 22.04 HVM-SSD AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ====================================
# Security Group for Backend
# ====================================

resource "aws_security_group" "backend_sg" {
  name        = "${var.instance_name}-sg"
  description = "Security group for backend application (Dittopedia)"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(var.tags, {
    Name = "${var.instance_name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Inbound: SSH (restricted)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.backend_sg.id
  description       = "SSH from Jenkins worker"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.ssh_ingress_cidr

  tags = {
    Name = "ssh-jenkins"
  }
}

# Inbound: Backend port 3000
resource "aws_vpc_security_group_ingress_rule" "backend" {
  security_group_id = aws_security_group.backend_sg.id
  description       = "Backend API port"
  from_port         = var.backend_port
  to_port           = var.backend_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0" # Public API access

  tags = {
    Name = "backend-api"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  security_group_id = aws_security_group.backend_sg.id
  description       = "Allow all outbound traffic"
  from_port         = -1
  to_port           = -1
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "outbound-all"
  }
}

# ====================================
# SSH Key Pair for EC2 Access
# ====================================

resource "aws_key_pair" "backend_key" {
  key_name_prefix = "${var.instance_name}-key-"
  public_key      = var.public_key

  tags = merge(var.tags, {
    Name = "${var.instance_name}-key"
  })
}

# ====================================
# EC2 Instance for Backend + Valkey
# ====================================

resource "aws_instance" "backend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.backend_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.backend_key.key_name

  lifecycle {
    ignore_changes = [
      # key_name_prefix génère un nom différent à chaque apply,
      # on ignore pour ne pas re-créer l'instance
      key_name,
      # most_recent = true pourrait pointer une nouvelle AMI à chaque run,
      # on ignore pour ne pas re-créer l'instance
      ami,
    ]
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = false # Can enable for production
  }

  monitoring    = true
  ebs_optimized = false

  tags = merge(var.tags, {
    Name = var.instance_name
  })

}

# Reference to managed backend instance
locals {
  backend_instance_id       = aws_instance.backend.id
  backend_public_ip         = aws_instance.backend.public_ip
  backend_private_ip        = aws_instance.backend.private_ip
  backend_security_group_id = aws_security_group.backend_sg.id
}

# ====================================
# Elastic IP (optional, for static IP)
# ====================================

# Uncomment to assign static public IP
# resource "aws_eip" "backend_eip" {
#   instance = local.backend_instance_id
#   domain   = "vpc"
#
#   tags = merge(var.tags, {
#     Name = "${var.instance_name}-eip"
#   })
#
#   depends_on = [aws_instance.backend]
# }

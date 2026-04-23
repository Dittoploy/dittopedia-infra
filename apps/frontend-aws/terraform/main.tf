terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ====================================
# Data Sources: Récupération automatique
# ====================================

# Récupère le VPC par défaut
data "aws_vpc" "default" {
  default = true
}

# Récupère les subnets du VPC par défaut
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Récupère l'AMI Ubuntu 22.04 la plus récente
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ====================================
# Ressources
# ====================================

resource "aws_key_pair" "frontend" {
  key_name   = var.key_name
  public_key = var.public_key
}

resource "aws_security_group" "frontend_sg" {
  name        = "${var.instance_name}-sg"
  description = "Allow HTTP and SSH for frontend EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    from_port   = var.frontend_port
    to_port     = var.frontend_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.instance_name}-sg"
  })
}

resource "aws_instance" "frontend" {
  ami                    = data.aws_ami.ubuntu.id
  subnet_id              = data.aws_subnets.default.ids[0]
  instance_type          = var.instance_type
  key_name               = aws_key_pair.frontend.key_name
  vpc_security_group_ids = [aws_security_group.frontend_sg.id]
  associate_public_ip_address = true

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
  
  tags = merge(var.tags, {
    Name = var.instance_name
  })
}
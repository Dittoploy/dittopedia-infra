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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_security_groups" "existing_docs" {
  filter {
    name   = "group-name"
    values = ["${var.instance_name}-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_instances" "existing_docs" {
  filter {
    name   = "tag:Name"
    values = [var.instance_name]
  }

  filter {
    name   = "instance-state-name"
    values = ["pending", "running"]
  }
}

data "aws_ami" "ubuntu_ami" {
  most_recent = true
  owners      = ["099720109477"]

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

locals {
  existing_sg_id       = length(data.aws_security_groups.existing_docs.ids) > 0 ? data.aws_security_groups.existing_docs.ids[0] : ""
  existing_instance_id = length(data.aws_instances.existing_docs.ids) > 0 ? data.aws_instances.existing_docs.ids[0] : ""
}

resource "aws_security_group" "docs" {
  count       = local.existing_sg_id == "" ? 1 : 0
  name        = "${var.instance_name}-sg"
  description = "Security group for docs app"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "Docs app"
    from_port   = var.docs_port
    to_port     = var.docs_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "docs" {
  count      = local.existing_instance_id == "" && trimspace(var.public_key) != "" ? 1 : 0
  key_name_prefix = "${var.key_name}-"
  public_key = var.public_key
}

resource "aws_instance" "docs" {
  count                  = local.existing_instance_id == "" ? 1 : 0
  ami                    = data.aws_ami.ubuntu_ami.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  key_name               = length(aws_key_pair.docs) > 0 ? aws_key_pair.docs[0].key_name : var.key_name
  vpc_security_group_ids = [local.existing_sg_id != "" ? local.existing_sg_id : aws_security_group.docs[0].id]

  tags = {
    Name = var.instance_name
  }
}

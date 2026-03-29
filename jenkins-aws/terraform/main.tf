# Terraform configuration for Jenkins AWS infrastructure

# --- S3 Bucket pour backups Jenkins ---
resource "aws_s3_bucket" "jenkins_backups" {
	bucket = "jenkins-backups-${var.project_name}"
	force_destroy = false
}

resource "aws_s3_bucket_versioning" "jenkins_backups_versioning" {
	bucket = aws_s3_bucket.jenkins_backups.id
	versioning_configuration {
		status = "Enabled"
	}
}

resource "aws_s3_bucket_public_access_block" "jenkins_backups_block" {
	bucket = aws_s3_bucket.jenkins_backups.id
	block_public_acls       = true
	block_public_policy     = true
	ignore_public_acls      = true
	restrict_public_buckets = true
}

# --- IAM Role et Policy pour Jenkins Master ---
data "aws_iam_policy_document" "jenkins_s3" {
	statement {
		actions = [
			"s3:PutObject",
			"s3:GetObject",
			"s3:ListBucket"
		]
		resources = [
			aws_s3_bucket.jenkins_backups.arn,
			"${aws_s3_bucket.jenkins_backups.arn}/*"
		]
	}
}

resource "aws_iam_role" "jenkins_master" {
	name = "jenkins-master-role-${var.project_name}"
	assume_role_policy = jsonencode({
		Version = "2012-10-17"
		Statement = [{
			Effect = "Allow"
			Principal = { Service = "ec2.amazonaws.com" }
			Action = "sts:AssumeRole"
		}]
	})
}

resource "aws_iam_policy" "jenkins_s3" {
	name   = "jenkins-s3-policy-${var.project_name}"
	policy = data.aws_iam_policy_document.jenkins_s3.json
}

resource "aws_iam_role_policy_attachment" "jenkins_s3_attach" {
	role       = aws_iam_role.jenkins_master.name
	policy_arn = aws_iam_policy.jenkins_s3.arn
}

resource "aws_iam_instance_profile" "jenkins_master" {
	name = "jenkins-master-profile-${var.project_name}"
	role = aws_iam_role.jenkins_master.name
}

# --- EC2 Jenkins Master ---
data "aws_ami" "ubuntu2204" {
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

resource "aws_instance" "jenkins_master" {
	ami                         = data.aws_ami.ubuntu2204.id
	instance_type               = "t3.medium"
	subnet_id                   = aws_subnet.public.id
	vpc_security_group_ids      = [aws_security_group.sg_jenkins_master.id]
	key_name                    = var.key_name
	associate_public_ip_address = true
	iam_instance_profile        = aws_iam_instance_profile.jenkins_master.name
	root_block_device {
		volume_size = 20
		volume_type = "gp3"
	}
	ebs_block_device {
		device_name = "/dev/xvdb"
		volume_size = 30
		volume_type = "gp3"
	}
	tags = {
		Name = "jenkins-master"
	}
}

resource "aws_eip" "jenkins_master_eip" {
	instance = aws_instance.jenkins_master.id
	vpc      = true
	depends_on = [aws_internet_gateway.igw]
}

# --- EC2 Jenkins Worker ---
resource "aws_instance" "jenkins_worker" {
	ami                    = data.aws_ami.ubuntu2204.id
	instance_type          = "t3.small"
	subnet_id              = aws_subnet.private.id
	vpc_security_group_ids = [aws_security_group.sg_jenkins_worker.id]
	key_name               = var.key_name
	root_block_device {
		volume_size = 20
		volume_type = "gp3"
	}
	tags = {
		Name = "jenkins-worker"
	}
}

# Configure AWS provider in Paris region
provider "aws" {
	region = var.aws_region
}


# Create a private isolated network (VPC)
resource "aws_vpc" "main" {
	cidr_block = var.vpc_cidr
	tags = {
		Name = "dittopedia-vpc"
	}
}


# Public subnet: resources here can access the Internet
resource "aws_subnet" "public" {
	vpc_id            = aws_vpc.main.id
	cidr_block        = var.public_subnet_cidr
	availability_zone = var.az
	map_public_ip_on_launch = true
	tags = {
		Name = "dittopedia-public-subnet"
	}
}


# Private subnet: resources here are not directly accessible from the Internet
resource "aws_subnet" "private" {
	vpc_id            = aws_vpc.main.id
	cidr_block        = var.private_subnet_cidr
	availability_zone = var.az
	tags = {
		Name = "dittopedia-private-subnet"
	}
}


# Internet Gateway: enables Internet access for the VPC
resource "aws_internet_gateway" "igw" {
	vpc_id = aws_vpc.main.id
	tags = {
		Name = "dittopedia-igw"
	}
}


# Public route table: routes Internet traffic via the IGW (Internet Gateway)
resource "aws_route_table" "public" {
	vpc_id = aws_vpc.main.id
	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = aws_internet_gateway.igw.id
	}
	tags = {
		Name = "dittopedia-public-rt"
	}
}


# Associate the public route table with the public subnet
resource "aws_route_table_association" "public_assoc" {
	subnet_id      = aws_subnet.public.id
	route_table_id = aws_route_table.public.id
}


# Security Group for Jenkins Master
resource "aws_security_group" "sg_jenkins_master" {
	name        = "sg_jenkins_master"
	description = "Allow Jenkins web and SSH access"
	vpc_id      = aws_vpc.main.id

	ingress {
		description = "Jenkins Web UI"
		from_port   = 8080
		to_port     = 8080
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	ingress {
		description = "SSH admin"
		from_port   = 22
		to_port     = 22
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	egress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
		Name = "sg_jenkins_master"
	}
}

# Security Group for Jenkins Worker
resource "aws_security_group" "sg_jenkins_worker" {
	name        = "sg_jenkins_worker"
	description = "Allow Jenkins agent and SSH from master"
	vpc_id      = aws_vpc.main.id

	ingress {
		description = "SSH from Jenkins master"
		from_port   = 22
		to_port     = 22
		protocol    = "tcp"
		security_groups = [aws_security_group.sg_jenkins_master.id]
	}

	ingress {
		description = "JNLP agent from Jenkins master"
		from_port   = 50000
		to_port     = 50000
		protocol    = "tcp"
		security_groups = [aws_security_group.sg_jenkins_master.id]
	}

	egress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
		Name = "sg_jenkins_worker"
	}
}

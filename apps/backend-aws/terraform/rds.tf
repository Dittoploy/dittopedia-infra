# ====================================
# RDS PostgreSQL (Conditional - Free Tier)
# ====================================

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  count       = var.enable_rds ? 1 : 0
  name        = "${var.instance_name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(var.tags, {
    Name = "${var.instance_name}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Allow PostgreSQL access from backend EC2
resource "aws_vpc_security_group_ingress_rule" "rds_from_backend" {
  count             = var.enable_rds ? 1 : 0
  security_group_id = aws_security_group.rds_sg[0].id
  description       = "PostgreSQL from backend EC2"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  referenced_security_group_id = local.backend_security_group_id

  tags = {
    Name = "postgres-from-backend"
  }
}

# RDS Subnet Group (using default VPC subnets)
resource "aws_db_subnet_group" "backend" {
  count       = var.enable_rds ? 1 : 0
  name_prefix = "${var.instance_name}-subnet-group-"
  subnet_ids  = data.aws_subnets.default.ids

  tags = merge(var.tags, {
    Name = "${var.instance_name}-subnet-group"
  })
}

# RDS PostgreSQL Instance (Free Tier: db.t3.micro)
resource "aws_db_instance" "backend_db" {
  count             = var.enable_rds ? 1 : 0
  identifier        = "${var.instance_name}-db"
  engine            = "postgres"
  engine_version    = var.rds_engine_version
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  storage_type      = "gp2"
  storage_encrypted = false

  db_name  = var.rds_database_name
  username = var.rds_master_username
  password = var.rds_master_password

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.backend[0].name
  vpc_security_group_ids = [aws_security_group.rds_sg[0].id]
  publicly_accessible    = false

  # Backup & Maintenance
  backup_retention_period = var.rds_backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  multi_az                = false

  # Parameters
  parameter_group_name = aws_db_parameter_group.backend[0].name
  deletion_protection  = false
  skip_final_snapshot  = true

  # Performance & Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]
  monitoring_interval             = 0

  tags = merge(var.tags, {
    Name = "${var.instance_name}-db"
  })

  depends_on = [
    aws_db_subnet_group.backend,
    aws_security_group.rds_sg,
  ]
}

# Custom RDS Parameter Group (PostgreSQL)
resource "aws_db_parameter_group" "backend" {
  count       = var.enable_rds ? 1 : 0
  name_prefix = "${var.instance_name}-pg-"
  family      = "postgres${var.rds_engine_version}"

  parameter {
    name  = "log_statement"
    value = "none"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, {
    Name = "${var.instance_name}-param-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ====================================
# Outputs for Ansible (RDS or EC2 fallback)
# ====================================

locals {
  database_url = var.enable_rds && length(aws_db_instance.backend_db) > 0 ? (
    "postgresql://${var.rds_master_username}:${var.rds_master_password}@${aws_db_instance.backend_db[0].endpoint}/${var.rds_database_name}"
  ) : (
    "postgresql://${var.rds_master_username}:${var.rds_master_password}@localhost:5432/${var.rds_database_name}"
  )

  database_host = var.enable_rds && length(aws_db_instance.backend_db) > 0 ? (
    split(":", aws_db_instance.backend_db[0].endpoint)[0]
  ) : (
    "localhost"
  )
}

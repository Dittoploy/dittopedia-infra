output "backend_instance_id" {
  description = "EC2 instance ID for backend"
  value       = local.backend_instance_id
}

output "backend_public_ip" {
  description = "Public IP address of backend EC2 instance"
  value       = local.backend_public_ip
}

output "backend_private_ip" {
  description = "Private IP address of backend EC2 instance"
  value       = local.backend_private_ip
}

output "backend_security_group_id" {
  description = "Security group ID for backend"
  value       = local.backend_security_group_id
}

output "rds_endpoint" {
  description = "RDS database endpoint (if enabled)"
  value       = try(aws_db_instance.backend_db[0].endpoint, "N/A - using EC2 fallback")
}

output "rds_database_name" {
  description = "RDS database name"
  value       = try(aws_db_instance.backend_db[0].db_name, "dittopedia")
}

output "valkey_port" {
  description = "Valkey cache port (internal to backend instance)"
  value       = var.valkey_port
}

output "backend_connection_string" {
  description = "Connection string for backend deployment configuration"
  value       = "Backend running at http://${local.backend_public_ip}:${var.backend_port}"
}

output "key_pair_name" {
  description = "Name of the SSH key pair created for this deployment"
  value       = aws_key_pair.backend_key.key_name
}

output "terraform_outputs" {
  description = "Outputs for Ansible inventory generation"
  value = {
    backend_public_ip = local.backend_public_ip
    backend_instance_id = local.backend_instance_id
    rds_endpoint = try(aws_db_instance.backend_db[0].endpoint, "")
    valkey_port = var.valkey_port
  }
}

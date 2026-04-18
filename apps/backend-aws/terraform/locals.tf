# Export Terraform outputs for Ansible dynamic inventory generation

output "terraform_state" {
  description = "Terraform state outputs for Jenkins/Ansible"
  value = {
    backend_public_ip  = local.backend_public_ip
    backend_private_ip = local.backend_private_ip
    backend_instance_id = local.backend_instance_id
    database_url       = local.database_url
    database_host      = local.database_host
    valkey_port        = var.valkey_port
    rds_enabled        = var.enable_rds
  }
  sensitive = true
}

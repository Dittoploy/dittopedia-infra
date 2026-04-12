locals {
  docs_instance_id = local.existing_instance_id != "" ? local.existing_instance_id : aws_instance.docs[0].id
  docs_public_ip   = local.existing_instance_id != "" ? data.aws_instances.existing_docs.public_ips[0] : aws_instance.docs[0].public_ip
}

output "docs_instance_id" {
  value = local.docs_instance_id
}

output "docs_public_ip" {
  value = local.docs_public_ip
}

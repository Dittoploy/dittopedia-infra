# outputs.tf
# Outputs for Jenkins AWS infrastructure

output "jenkins_master_public_ip" {
	description = "Adresse IP publique de l'instance Jenkins Master"
	value       = aws_eip.jenkins_master_eip.public_ip
}

output "jenkins_master_private_ip" {
	description = "Adresse IP privée de l'instance Jenkins Master"
	value       = aws_instance.jenkins_master.private_ip
}

output "jenkins_worker_private_ip" {
	description = "Adresse IP privée de l'instance Jenkins Worker"
	value       = aws_instance.jenkins_worker.private_ip
}

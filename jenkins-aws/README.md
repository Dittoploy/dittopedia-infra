
# Déploiement Jenkins sur AWS avec Terraform & Ansible

## 1. Prérequis

- Terraform >= 1.0
- Ansible >= 2.10
- AWS CLI configuré (`aws configure`)
- Une clé SSH pour accéder aux instances EC2 (ex: `~/.ssh/jenkins_key.pem`)

## 2. Configuration initiale

- Configurez vos identifiants AWS :
	```sh
	aws configure
	```
- Renseignez les variables dans `terraform/terraform.tfvars` (notamment `key_name`, `project_name`...)
- Vérifiez que la clé SSH existe sur AWS EC2 et en local

## 3. Déploiement en 4 commandes

```sh
cd terraform
terraform init
terraform apply
```
- Récupérez les outputs Terraform : IP publique du master, IP privée du worker
- Mettez à jour `ansible/inventory/hosts.ini` avec ces adresses

```sh
cd ../ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

## 4. Accès Jenkins

- Accédez à l'interface Jenkins :
	- URL : `http://<IP_publique_master>:8080`
- Le mot de passe initial se trouve sur le master :
	```sh
	sudo cat /var/lib/jenkins/secrets/initialAdminPassword
	```

## 5. Ajout du worker dans Jenkins

- Dans l'interface Jenkins, ajoutez un nouvel agent (node) :
	- Nom : identique à `agent_name` dans le rôle Ansible worker
	- Récupérez le secret d'enregistrement et l'URL JNLP
	- Relancez le playbook Ansible worker si besoin avec les bonnes variables

## 6. Destruction de l'infrastructure

Pour tout supprimer :
```sh
cd terraform
terraform destroy
```

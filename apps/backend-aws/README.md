# Déploiement Backend AWS avec Jenkins, Terraform et Ansible

Ce dossier contient la stack de déploiement du backend Dittopedia sur AWS.
Le but est de fournir un guide pas-à-pas, directement exécutable, pour le job Jenkins de déploiement backend.

## 1. Prérequis

- Jenkins master et worker opérationnels (voir le guide jenkins-aws)
- Un job Jenkins pipeline pour dittopedia-back
- Identifiants Jenkins configurés (voir README jenkins-worker)
- Branche infra à jour : feature/backend-aws-deployment
- Docker Hub accessible depuis Jenkins
- Identifiants AWS valides pour Terraform
- Ansible ≥ 2.10 installé sur le worker Jenkins

## 2. Préparation Jenkins

### 2.1 Configurer les credentials Jenkins

dittopedia-rds-password (Secret text)
- **Kind:** Secret text
- **Secret:** Mot de passe RDS (voir .env DITTOPEDIA_RDS_PASSWORD)
- **ID:** `dittopedia-rds-password`
- **Description:** RDS master password for database
- **Scope:** Global

### 2.2 Créer le job

- Name: Deploy-Dittopedia-Backend-Staging
- Type: Pipeline script from SCM
- Repository URL: https://github.com/Dittoploy/dittopedia-back.git
- Branch specifier: */staging-aws-1
- Script path: Jenkinsfile
- Agent label: worker1

### 2.3 Activer le déclenchement automatique (webhook GitHub)

1) URL webhook GitHub:

~~~text
http://jenkins-master-ip:8080/github-webhook/
~~~

2) Configuration du webhook dans GitHub (repo `dittopedia-back`):
- Settings -> Webhooks -> Add webhook
- Payload URL: `http://jenkins-master-ip:8080/github-webhook/`
- Content type: `application/json`
- Secret: valeur à récupérer dans le .env
- SSL verification: `Disable` (car notre Jenkins AWS est en HTTP)
- Events: `Just the push event`

3) Configuration du job Jenkins:
- Pipeline from SCM (déjà en place)
- Branch specifier: `*/staging-aws-1`
- Script path: `Jenkinsfile`
- Cocher `GitHub hook trigger for GITScm polling`
- Sauvegarder la configuration du job après vérification.

## 3. Configuration appliquée par le Jenkinsfile

Variables principales:
- DOCKER_IMAGE_NAME: dittopedia-back
- INFRA_REPO_URL: https://github.com/Dittoploy/dittopedia-infra.git
- INFRA_REPO_BRANCH: feature/backend-aws-deployment
- AWS_REGION: eu-west-3
- EC2_INSTANCE_NAME: dittopedia-backend-staging
- EC2_INSTANCE_TYPE: t3.small
- EC2_KEY_NAME: dittopedia-jenkins-key
- EC2_SSH_USER: ubuntu
- ENABLE_RDS: true
- BACKEND_PORT: 3000
- ENABLE_SONAR: true

Comportement par branche:
- main:
  - Build + test + push image (tag latest)
  - Pas de deploy backend AWS
- staging-aws-1:
  - Build + test + push image (tag staging-aws-1)
  - Deploy backend AWS actif

**Note:** La clé SSH publique est extraite automatiquement par le Jenkinsfile depuis `/home/jenkins/.ssh/ec2-staging-ssh` (clé privée stockée sur le worker) - pas de credential séparé nécessaire.

## 4. Workflow de déploiement (staging-aws-1)

1. Build app backend avec npm/bun
2. Exécuter les tests (Jest, SonarQube optionnel)
3. Build image Docker runtime
4. Push image vers Docker Hub (tag staging-aws-1)
5. Clone du repo infra (feature/backend-aws-deployment)
6. Préparation de la clé publique pour Terraform
7. Terraform apply dans apps/backend-aws/terraform
8. Récupération de backend_public_ip
9. Test SSH vers l'instance
10. Ansible deploy dans apps/backend-aws/ansible
11. Démarrage conteneur backend en 3000
12. Démarrage conteneur Valkey en 6379
13. Vérification des endpoints de santé

## 5. Infrastructure apps/backend-aws

Terraform:
- Région: eu-west-3
- Instance type: t3.small
- OS: Ubuntu 22.04
- Port API backend: 3000
- Port cache Valkey: 6379
- Creation EC2 uniquement si absente
- Création RDS PostgreSQL (ou fallback EC2 si `enable_rds = false`)
- Key pair créée automatiquement lors de création EC2

Ansible:
- Rôle: backend_app
- Installation Docker + Docker Compose
- Pull image depuis Docker Hub
- Configuration Valkey (port 6379)
- Configuration backend (port 3000, variables d'environnement)
- Validation des endpoints de santé

## 6. Ressources AWS créées et destruction

### 6.1 Ressources créées par cette stack

Selon le contexte (première création ou update), cette stack peut créer:

- Une instance EC2 backend
  - Tag Name: dittopedia-backend-staging
  - t3.small Ubuntu 22.04
- Une base de données RDS PostgreSQL (si `enable_rds = true`)
  - Nom: dittopedia-backend-staging
  - db.t3.micro (couche gratuite)
- Un Security Group backend (si absent)
  - Nom: dittopedia-backend-staging-sg
- Une Key Pair AWS (si création instance avec public_key fourni)
  - Prefix courant: dittopedia-jenkins-key-fallback-

Notes:
- Le provider AWS utilise la région eu-west-3 par défaut.
- Le déploiement applicatif (Docker pull/run, migrations) est fait via Ansible sur l'instance EC2.

### 6.2 Destruction avec Terraform (si state disponible)
<!-- TODO : Automatiser cette partie avec un .sh -->

Important:
- Cette commande ne supprime proprement que les ressources presentes dans le state utilise.
- Si le `apply` a ete lance depuis Jenkins avec un state local du workspace, il faut executer le `destroy` depuis ce meme workspace Jenkins (ou recuperer exactement ce `terraform.tfstate`).

~~~sh
ssh jenkins-worker

cd /var/jenkins/workspace/Deploy-Dittopedia-Backend-Staging/infra-workdir/apps/backend-aws/terraform
terraform init

export AWS_ACCESS_KEY_ID="ton-access-key-id"
export AWS_SECRET_ACCESS_KEY="ta-secret-access-key"
export AWS_DEFAULT_REGION="eu-west-3"

sudo -E terraform destroy
~~~

Note:
`public_key` pour la trouver, sur votre machine locale:
~~~sh
cat ~/.ssh/dittopedia_jenkins_key.pem
~~~
(Copier tout sur une seule ligne)

`rds_master_password` à retrouver dans le .env

`ssh_ingress_cidr` à trouver via `curl -s https://checkip.amazonaws.com` depuis le worker (en rajoutant /32 à la fin)
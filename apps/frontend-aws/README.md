# Déploiement Frontend AWS avec Jenkins, Terraform et Ansible

Ce dossier contient la stack de déploiement du frontend Dittopedia sur AWS.
Le but est de fournir un guide pas-à-pas, directement exécutable, pour le job Jenkins de déploiement frontend.

## 1. Prérequis

- Jenkins master et worker opérationnels (voir le guide jenkins-aws)
- Un job Jenkins pipeline pour dittopedia-front
- Credentials Jenkins configurés (voir README jenkins-worker)
- Branche infra à jour : staging-aws-1
- Docker Hub accessible depuis Jenkins
- Identifiants AWS valides pour Terraform
- Ansible ≥ 2.10 installé sur le worker Jenkins

## 2. Préparation Jenkins

### 2.1 Créer le job

- Name: Deploy-Dittopedia-Front-Staging
- Type: Pipeline script from SCM
- Repository URL: https://github.com/Dittoploy/dittopedia-front.git
- Branch specifier: */staging-aws-1
- Script path: Jenkinsfile
- Agent label: worker1

### 2.2 Activer le déclenchement automatique (webhook GitHub)

1) URL webhook GitHub:

~~~text
http://jenkins-master-ip:8080/github-webhook/
~~~

2) Configuration du webhook dans GitHub (repo `dittopedia-front`):
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
- DOCKER_IMAGE_NAME: dittopedia-front
- INFRA_REPO_URL: https://github.com/Dittoploy/dittopedia-infra.git
- INFRA_REPO_BRANCH: staging-aws-1
- AWS_REGION: eu-west-3
- EC2_INSTANCE_NAME: dittopedia-front-staging
- EC2_INSTANCE_TYPE: t3.micro
- EC2_KEY_NAME: dittopedia-jenkins-key
- EC2_SSH_USER: ubuntu
- FRONTEND_PORT: 3001
- ENABLE_SONAR: false

Comportement par branche:
- main:
  - Build + push image (tag latest)
  - Pas de deploy frontend AWS
- staging-aws-1:
  - Build + push image (tag staging-aws-1)
  - Deploy frontend AWS actif

## 4. Workflow de déploiement (staging-aws-1)

1. Build app frontend avec npm/bun
2. Build image Docker runtime
3. Push image vers Docker Hub (tag staging-aws-1)
4. Clone du repo infra (branche staging-aws-1)
5. Préparation de la clé publique pour Terraform
6. Terraform apply dans apps/frontend-aws/terraform
7. Récupération de frontend_public_ip
8. Test SSH vers l'instance
9. Ansible deploy dans apps/frontend-aws/ansible
10. Démarrage conteneur frontend en 3001
11. Vérification du endpoint de santé

## 5. Infrastructure apps/frontend-aws

Terraform:
- Région: eu-west-3
- Instance type: t3.micro
- OS: Ubuntu 22.04
- Port API frontend: 3001
- Création EC2 uniquement si absente
- Key pair créée automatiquement lors de création EC2

Ansible:
- Rôle: frontend_app
- Installation Docker
- Pull image depuis Docker Hub
- Configuration frontend (port 3001, variables d'environnement)
- Validation du endpoint de santé

## 6. Ressources AWS créées et destruction

### 6.1 Ressources créées par cette stack

- Une instance EC2 frontend
  - Tag Name: dittopedia-front-staging
  - t3.micro Ubuntu 22.04
- Un Security Group frontend (si absent)
  - Nom: dittopedia-frontend-staging-sg
- Une Key Pair AWS (si création instance avec public_key fourni)
  - Prefix courant: dittopedia-jenkins-key-fallback-

Notes:
- Le provider AWS utilise la région eu-west-3 par défaut.
- Le déploiement applicatif (Docker pull/run) est fait via Ansible sur l'instance EC2.

### 6.2 Destruction avec Terraform (si state disponible)
<!-- TODO : Automatiser cette partie avec un .sh -->

Important:
- Cette commande ne supprime proprement que les ressources presentes dans le state utilise.
- Si le `apply` a ete lance depuis Jenkins avec un state local du workspace, il faut executer le `destroy` depuis ce meme workspace Jenkins (ou recuperer exactement ce `terraform.tfstate`).

~~~sh
ssh jenkins-worker

cd /var/jenkins/workspace/Deploy-Dittopedia-Front-Staging/infra-workdir/apps/frontend-aws/terraform
terraform init

export AWS_ACCESS_KEY_ID="ton-access-key-id"
export AWS_SECRET_ACCESS_KEY="ta-secret-access-key"
export AWS_DEFAULT_REGION="eu-west-3"

sudo -E terraform destroy
~~~

Note:
`private_key` n'est pas nécessaire

`public_key` pour la trouver, sur votre machine locale:
~~~sh
cat ~/.ssh/dittopedia_jenkins_key.pem
~~~
(Copier tout sur une seule ligne)

`rds_master_password` à retrouver dans le .env

`ssh_ingress_cidr` à trouver via `curl -s https://checkip.amazonaws.com` depuis le worker (en rajoutant /32 à la fin)

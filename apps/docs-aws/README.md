# Deploiement Docs AWS avec Jenkins, Terraform et Ansible

Ce dossier contient la stack de deploiement de la documentation Dittopedia sur AWS.
Le but est de fournir un guide pas-a-pas, directement executable, pour le job Jenkins de deploiement docs.

## 1. Prerequis

- Jenkins master et worker operationnels (voir le guide jenkins-aws)
- Un job Jenkins pipeline pour dittopedia-docs
- Credentials Jenkins configurees (Voir README jenkins-worker)
- Branche infra a jour: feature/deploy-dittopedia-docs
- Docker Hub accessible depuis Jenkins
- AWS credentials valides pour Terraform

## 2. Preparation Jenkins

### 2.1 Créer le job

- Name: Deploy-Dittopedia-Docs-Staging
- Type: Pipeline script from SCM
- Repository URL: https://github.com/Dittoploy/dittopedia-docs.git
- Branch specifier: */staging-aws-1
- Script path: Jenkinsfile
- Agent label: worker1

### 2.2 Activer le déclenchement automatique (webhook GitHub)

1) URL webhook GitHub:

~~~text
http://jenkins-master-ip:8080/github-webhook/
~~~

2) Configuration du webhook dans GitHub (repo `dittopedia-docs`):
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

## 3. Configuration appliquee par le Jenkinsfile

Variables principales:
- DOCKER_IMAGE_NAME: dittopedia-docs
- INFRA_REPO_URL: https://github.com/Dittoploy/dittopedia-infra.git
- INFRA_REPO_BRANCH: feature/deploy-dittopedia-docs
- AWS_REGION: eu-west-3
- EC2_INSTANCE_NAME: dittopedia-docs-staging
- EC2_INSTANCE_TYPE: t3.small
- EC2_KEY_NAME: dittopedia-jenkins-key
- EC2_SSH_USER: ubuntu
- ENABLE_SONAR: false

Comportement par branche:
- main:
  - Build + push image (tag latest)
  - Pas de deploy docs AWS
- staging-aws-1:
  - Build + push image (tag staging-aws-1)
  - Deploy docs AWS actif

## 4. Workflow de deploiement (staging-aws-1)

1. Build app docs avec bun/next
2. Build image Docker runtime
3. Push image vers Docker Hub
4. Clone du repo infra (feature/deploy-dittopedia-docs)
5. Preparation de la cle publique pour Terraform
6. Terraform apply dans apps/docs-aws/terraform
7. Recuperation de docs_public_ip
8. Test SSH vers linstance
9. Ansible deploy dans apps/docs-aws/ansible
10. Demarrage conteneur docs en 80:3000

## 5. Infrastructure apps/docs-aws

Terraform:
- Region: eu-west-3
- Instance type: t3.small
- Port public docs: 80
- Creation EC2 uniquement si absente
- Key pair creee automatiquement lors de creation EC2

Ansible:
- Role: docs_app
- Pull image depuis Docker Hub
- Relance le conteneur docs
- Mapping port: docs_host_port:3000 (actuellement 80:3000)

## 6. Ressources AWS creees et destruction

### 6.1 Ressources creees par cette stack

Selon le contexte (premiere creation ou update), cette stack peut creer:

- Une instance EC2 docs
  - Tag Name: dittopedia-docs-staging
- Un Security Group docs (si absent)
  - Nom: dittopedia-docs-staging-sg
- Une Key Pair AWS (si creation instance avec public_key fourni)
  - Prefix courant: dittopedia-jenkins-key-fallback-

Notes:
- Le provider AWS utilise la region eu-west-3 par defaut.
- Le deployment applicatif (Docker pull/run) est fait via Ansible sur linstance EC2.

### 6.2 Destruction avec Terraform (si state disponible)
<!-- TODO : Automatiser cette partie avec un .sh -->

Important:
- Cette commande ne supprime proprement que les ressources presentes dans le state utilise.
- Si le `apply` a ete lance depuis Jenkins avec un state local du workspace, il faut executer le `destroy` depuis ce meme workspace Jenkins (ou recuperer exactement ce `terraform.tfstate`).

~~~sh
ssh jenkins-worker

cd /var/jenkins/workspace/Deploy-Dittopedia-Docs-Staging/infra-workdir/apps/docs-aws/terraform
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
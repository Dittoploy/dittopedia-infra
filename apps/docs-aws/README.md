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

Si vous disposez du state Terraform de ce composant:

~~~sh
cd apps/docs-aws/terraform
terraform init
terraform destroy -auto-approve \
  -var="aws_region=eu-west-3" \
  -var="instance_name=dittopedia-docs-staging" \
  -var="instance_type=t3.small" \
  -var="key_name=dittopedia-jenkins-key-fallback"
~~~

### 6.3 Destruction manuelle AWS CLI (si state indisponible)

Cas frequent: le deployment Jenkins utilise un dossier temporaire sans backend distant,
donc le state nest pas conserve localement.

1) Trouver les instances docs:

~~~sh
aws ec2 describe-instances \
  --region eu-west-3 \
  --filters Name=tag:Name,Values=dittopedia-docs-staging Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query "Reservations[].Instances[].InstanceId" \
  --output text
~~~

2) Terminer les instances trouvees:

~~~sh
aws ec2 terminate-instances --region eu-west-3 --instance-ids <INSTANCE_ID_1> <INSTANCE_ID_2>
~~~

3) Lister puis supprimer le SG docs:

~~~sh
aws ec2 describe-security-groups \
  --region eu-west-3 \
  --filters Name=group-name,Values=dittopedia-docs-staging-sg \
  --query "SecurityGroups[].GroupId" \
  --output text
~~~

~~~sh
aws ec2 delete-security-group --region eu-west-3 --group-id <SG_ID>
~~~

4) Lister puis supprimer les key pairs fallback:

~~~sh
aws ec2 describe-key-pairs \
  --region eu-west-3 \
  --query "KeyPairs[?starts_with(KeyName, 'dittopedia-jenkins-key-fallback-')].KeyName" \
  --output text
~~~

~~~sh
aws ec2 delete-key-pair --region eu-west-3 --key-name <KEY_NAME>
~~~

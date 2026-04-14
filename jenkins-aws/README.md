# Déploiement Jenkins sur AWS avec Terraform & Ansible

## 1. Prérequis

- Terraform >= 1.0
- Ansible >= 2.10
- AWS CLI configuré (`aws configure`)
- Une clé SSH pour accéder aux instances EC2 (ex: `~/.ssh/dittopedia_jenkins_key.pem`)

## 2. Configuration initiale

Configurez vos identifiants AWS avec la commande suivante :

~~~sh
aws configure
~~~

Cette commande vous demandera :
- **AWS Access Key ID** et **AWS Secret Access Key** : à générer dans la console AWS (IAM > Users > Security credentials)
- **Default region name** : par exemple `eu-west-3` pour Paris
- **Default output format** : `json` (ou laissez vide)

Renseignez les variables dans `terraform/terraform.tfvars` :
- `key_name` : **Nom exact de la key pair EC2** à utiliser pour SSH (doit exister sur AWS et le fichier .pem correspondant doit être présent sur votre machine, ex : `~/.ssh/dittopedia_jenkins_key.pem`)
- `project_name` : **Nom du projet** (sert de préfixe à toutes les ressources AWS créées, ex : `dittopedia`)

Vérifiez que la clé SSH existe sur AWS EC2 et en local.

## 3. Déploiement

### 3.1 Terraform

~~~sh
cd terraform
terraform init
terraform apply
~~~

Si vous obtenez une erreur liée au Free Tier ou au type d'instance, reportez-vous à la section "Erreurs courantes" en fin de document.

### 3.2 Bootstrap automatique

Après `terraform apply`, placez-vous dans le répertoire racine de `jenkins-aws/`, puis lancez le script de bootstrap. Le script suppose d'être exécuté depuis ce répertoire (il utilise notamment `cd terraform`). Il met à jour automatiquement `~/.ssh/config`, `hosts.ini`, `defaults/main.yml` du worker, et copie la clé SSH sur le master :

~~~sh
cd ..                                                             # Retourner à jenkins-aws/ (racine du module)
chmod +x bootstrap.sh                                             # Rendre le script exécutable
SSH_KEY_PATH=~/.ssh/dittopedia_jenkins_key.pem ./bootstrap.sh     # Exécuter depuis jenkins-aws/
~~~

> **Note** : Le script lit les outputs Terraform directement — assurez-vous d'avoir bien lancé `terraform apply` avant (depuis `jenkins-aws/terraform/`).

### 3.3 Lancement du playbook Jenkins Master

~~~sh
cd ansible
ansible-playbook -i inventory/hosts.ini site.yml --limit jenkins_master --ask-vault-pass
~~~

Si besoin, voir le `.env` et regarder la valeur de `ANSIBLE_VAULT_PASS`.

### 3.4 Configuration Jenkins UI (master)

Accédez à l'interface Jenkins :
- URL : `http://<IP_publique_master>:8080`

Récupérez le mot de passe initial :

~~~sh
ssh jenkins-master
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
~~~

Une fois connecté, effectuez ces étapes **avant** de lancer le playbook worker :

**a) Corriger l'URL Jenkins** (indispensable pour que le worker se connecte via l'IP privée) :
- **Manage Jenkins → System → Jenkins URL**
- Remplacez l'URL par : `http://<IP_privée_master>:8080/`
- Sauvegardez

**b) Activer le port agent JNLP** :
- **Manage Jenkins → Security → Agents**
- **TCP port for inbound agents** : sélectionnez **Fixed** → `50000`
- Sauvegardez

**c) Créer le node worker** :
- **Manage Jenkins → Nodes → New Node**
- Nom : identique à `agent_name` dans `ansible/roles/jenkins_worker/defaults/main.yml` (ex : `worker1`)
- Type : **Permanent Agent**
- Remote root directory : `/var/jenkins`
- Launch method : **Launch agent by connecting it to the controller**
- Sauvegardez
- Cliquez sur le node créé et copiez le **secret** affiché dans la commande de connexion

### 3.5 Configuration du secret worker

Mettez à jour le vault Ansible avec le secret récupéré à l'étape précédente :

~~~sh
ansible-vault edit inventory/group_vars/jenkins_worker/vault.yml
~~~

~~~yaml
agent_secret: "<secret_copié_depuis_jenkins_ui>"
~~~

### 3.6 Lancement du playbook Jenkins Worker

~~~sh
ansible-playbook -i inventory/hosts.ini site.yml --limit jenkins_worker --ask-vault-pass
~~~

### 3.7 Vérification du worker

Vérifiez que l'agent est bien connecté :

~~~sh
ssh jenkins-worker
sudo systemctl status jenkins-agent
sudo journalctl -u jenkins-agent -f
~~~

Vous devriez voir `INFO: Connected` dans les logs. Le worker doit également apparaître comme **connecté** dans **Manage Jenkins → Nodes**.

### 3.8 Bootstrap worker (clé de déploiement)

Pour automatiser la préparation SSH du worker (même logique orientée bootstrap), lancez le script dédié :

~~~sh
cd ..
chmod +x bootstrap-worker.sh
SSH_KEY_PATH=~/.ssh/dittopedia_jenkins_key.pem \
DEPLOY_KEY_PATH=~/.ssh/dittopedia_jenkins_key.pem \
./bootstrap-worker.sh
~~~

Variables optionnelles :
- `DEPLOY_KEY_PATH` : clé privée à déposer sur le worker (par défaut = `SSH_KEY_PATH`)
- `WORKER_KEY_DEST_PATH` : chemin cible sur le worker (par défaut `/var/jenkins/.ssh/dittopedia_deploy_key.pem`)

## 4. Credentials Jenkins à créer

Créez les credentials Jenkins suivants (scope global) pour les pipelines Dittopedia :

- **`dockerhub-creds`**
  - Type : Username with password
  - Username : login Docker Hub
  - Password : Docker Hub token
- **`aws-deploy-creds`**
  - Type : Username with password
  - Username : AWS Access Key ID
  - Password : AWS Secret Access Key
- **`ec2-staging-ssh`**
  - Type : SSH Username with private key
  - Username : `ubuntu`
  - Private key : clé privée SSH de déploiement (`cat ~/.ssh/dittopedia_jenkins_key.pem`)
- **`ssh-ingress-cidr-default`**
  - Type : Secret text
  - Valeur : CIDR SSH autorisé unique (Depuis le worker `ssh jenkins-worker`, executez `curl -s https://checkip.amazonaws.com`)
  - Exemple : `15.236.153.189/32`
  - Interdit : `0.0.0.0/0`
- **`github-webhook-shared-secret`**
  - Type : Secret text
  - Valeur : valeur de DITTOPEDIA_INFRA_WEBHOOK dans le .env

Note : la pipeline docs peut prendre un `SSH_INGRESS_CIDR` manuel au lancement du job, qui reste prioritaire. Si ce paramètre est vide, la valeur du credential `ssh-ingress-cidr-default` est utilisée.

## 5. Destruction de l'infrastructure

Pour tout supprimer :

~~~sh
cd terraform
terraform destroy
~~~

## Erreurs courantes

### 1. Erreur Free Tier : type d'instance non éligible

Si lors de `terraform apply` vous obtenez une erreur du type :

~~~
Error: creating EC2 Instance: ... api error InvalidParameterCombination: The specified instance type is not eligible for Free Tier.
~~~

Cela signifie que le type d'instance choisi (ex : `t3.medium`) n'est pas inclus dans le Free Tier AWS.

Pour trouver les types d'instances éligibles Free Tier dans votre région :

~~~sh
aws ec2 describe-instance-types \
  --region <votre-region> \
  --filters Name=free-tier-eligible,Values=true \
  --query "InstanceTypes[*].InstanceType" \
  --output table
~~~

Remplacez `<votre-region>` par la région souhaitée (ex : `eu-west-3`).

### 2. Worker déconnecté dans Jenkins UI

Si le worker apparaît déconnecté après le playbook :

~~~sh
ssh jenkins-worker
sudo journalctl -u jenkins-agent -n 50 --no-pager
~~~

Causes fréquentes :
- **Jenkins URL** pas en IP privée → corriger dans **Manage Jenkins → System → Jenkins URL**
- **Port 50000** non activé → corriger dans **Manage Jenkins → Security → Agents**
- **Secret incorrect** → vérifier le vault et relancer le playbook worker

### 3. Cycle de dépendance Terraform sur les Security Groups

Si vous obtenez `Error: Cycle: aws_security_group.sg_jenkins_master, aws_security_group.sg_jenkins_worker`, utilisez des `aws_security_group_rule` séparées pour les règles croisées entre security groups.
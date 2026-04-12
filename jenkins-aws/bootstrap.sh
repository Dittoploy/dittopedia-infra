#!/bin/bash
set -e

# ── Couleurs ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Bootstrap Jenkins Infrastructure ===${NC}"

# ── 1. Récupération des IPs depuis Terraform ────────────────────────────────
echo -e "${YELLOW}[1/4] Récupération des outputs Terraform...${NC}"
cd terraform

MASTER_PUBLIC_IP=$(terraform output -raw jenkins_master_public_ip)
MASTER_PRIVATE_IP=$(terraform output -raw jenkins_master_private_ip)
WORKER_PRIVATE_IP=$(terraform output -raw jenkins_worker_private_ip)
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/dittopedia_jenkins_key.pem}"

echo "  Master public  : $MASTER_PUBLIC_IP"
echo "  Master private : $MASTER_PRIVATE_IP"
echo "  Worker private : $WORKER_PRIVATE_IP"

# ── 2. Mise à jour de ~/.ssh/config ─────────────────────────────────────────
echo -e "${YELLOW}[2/4] Mise à jour de ~/.ssh/config...${NC}"

# Crée le répertoire ~/.ssh et le fichier de config s'ils n'existent pas
mkdir -p ~/.ssh
touch ~/.ssh/config
chmod 600 ~/.ssh/config

# Supprime les anciens blocs jenkins
sed -i.bak '/^Host jenkins-master$/,/^$/d' ~/.ssh/config
sed -i.bak '/^Host jenkins-worker$/,/^$/d' ~/.ssh/config

cat >> ~/.ssh/config << EOF

Host jenkins-master
    HostName $MASTER_PUBLIC_IP
    User ubuntu
    IdentityFile $SSH_KEY
    IdentitiesOnly yes

Host jenkins-worker
    HostName $WORKER_PRIVATE_IP
    User ubuntu
    IdentityFile $SSH_KEY
    IdentitiesOnly yes
    ProxyJump jenkins-master
    StrictHostKeyChecking no
EOF

echo "  ~/.ssh/config mis à jour"

# ── 3. Mise à jour de hosts.ini ─────────────────────────────────────────────
echo -e "${YELLOW}[3/4] Mise à jour de hosts.ini...${NC}"
cd ../ansible

cat > inventory/hosts.ini << EOF
[jenkins_master]
$MASTER_PUBLIC_IP ansible_user=ubuntu ansible_ssh_private_key_file=$SSH_KEY

[jenkins_worker]
jenkins-worker ansible_user=ubuntu ansible_ssh_private_key_file=$SSH_KEY
EOF

echo "  inventory/hosts.ini mis à jour"

# ── 4. Copie de la clé SSH sur le master ────────────────────────────────────
echo -e "${YELLOW}[4/4] Copie de la clé SSH sur le master...${NC}"

# Attendre que le master soit disponible
echo "  Attente du master SSH..."
until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 jenkins-master "echo ok" 2>/dev/null; do
  echo "  Master pas encore prêt, retry dans 5s..."
  sleep 5
done

scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  "$SSH_KEY" \
  ubuntu@$MASTER_PUBLIC_IP:~/.ssh/
ssh jenkins-master "chmod 600 ~/.ssh/$(basename $SSH_KEY)"

echo "  Clé SSH copiée sur le master"

# ── 5. Mise à jour de defaults/main.yml worker ──────────────────────────────
echo -e "${YELLOW}[5/5] Mise à jour de l'IP master dans le rôle worker...${NC}"

sed -i.bak "s/^jenkins_master_ip:.*/jenkins_master_ip: \"$MASTER_PRIVATE_IP\"/" \
  roles/jenkins_worker/defaults/main.yml

echo "  jenkins_master_ip mis à jour → $MASTER_PRIVATE_IP"

# ── Résumé ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}=== Bootstrap terminé ===${NC}"
echo ""
echo "Prochaines étapes :"
echo "  1. ansible-playbook -i inventory/hosts.ini site.yml --limit jenkins_master --ask-vault-pass"
echo "  2. Configurer Jenkins UI : http://$MASTER_PUBLIC_IP:8080"
echo "     - Jenkins URL → http://$MASTER_PRIVATE_IP:8080/"
echo "     - Activer port agent JNLP → 50000"
echo "     - Créer le node worker et copier le secret"
echo "  3. Mettre à jour le vault avec le secret worker"
echo "  4. ansible-playbook -i inventory/hosts.ini site.yml --limit jenkins_worker --ask-vault-pass"
echo "  5. SSH_KEY_PATH=$SSH_KEY DEPLOY_KEY_PATH=$SSH_KEY ./bootstrap-worker.sh"
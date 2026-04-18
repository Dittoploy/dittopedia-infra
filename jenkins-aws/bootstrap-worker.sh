#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/dittopedia_jenkins_key.pem}"
DEPLOY_KEY="${DEPLOY_KEY_PATH:-$SSH_KEY}"
WORKER_KEY_DEST="${WORKER_KEY_DEST_PATH:-/var/jenkins/.ssh/dittopedia_deploy_key.pem}"
TMP_REMOTE_KEY="/tmp/dittopedia_deploy_key.pem"
RETRY_INTERVAL_SECONDS="${RETRY_INTERVAL_SECONDS:-5}"
MAX_RETRIES="${MAX_RETRIES:-24}"
MASTER_SSH_TARGET="${MASTER_SSH_TARGET:-jenkins-master}"
WORKER_SSH_TARGET="${WORKER_SSH_TARGET:-jenkins-worker}"

SSH_MODE="proxyjump"

ssh_via_master() {
  if [ "$SSH_MODE" = "alias" ]; then
    ssh -o ConnectTimeout=8 "$WORKER_SSH_TARGET" "$@"
  else
    ssh -i "$SSH_KEY" \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=8 \
      -J "ubuntu@$MASTER_PUBLIC_IP" \
      "ubuntu@$WORKER_PRIVATE_IP" "$@"
  fi
}

scp_to_worker() {
  local source_file="$1"
  local target_path="$2"

  if [ "$SSH_MODE" = "alias" ]; then
    scp -o ConnectTimeout=8 "$source_file" "$WORKER_SSH_TARGET:$target_path"
  else
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ProxyJump="ubuntu@$MASTER_PUBLIC_IP" "$source_file" "ubuntu@$WORKER_PRIVATE_IP:$target_path"
  fi
}

echo -e "${GREEN}=== Bootstrap Jenkins Worker Deploy Key ===${NC}"

if [ ! -f "$SSH_KEY" ]; then
  echo "Erreur: SSH_KEY_PATH introuvable: $SSH_KEY" >&2
  exit 1
fi

if [ ! -f "$DEPLOY_KEY" ]; then
  echo "Erreur: DEPLOY_KEY_PATH introuvable: $DEPLOY_KEY" >&2
  exit 1
fi

echo -e "${YELLOW}[1/5] Récupération des outputs Terraform...${NC}"
cd "$TERRAFORM_DIR"

MASTER_PUBLIC_IP="$(terraform output -raw jenkins_master_public_ip)"
WORKER_PRIVATE_IP="$(terraform output -raw jenkins_worker_private_ip)"

echo "  Master public : $MASTER_PUBLIC_IP"
echo "  Worker private: $WORKER_PRIVATE_IP"

echo -e "${YELLOW}[2/5] Vérification de la disponibilité SSH du worker...${NC}"
if ssh -o ConnectTimeout=8 "$WORKER_SSH_TARGET" "echo ok" >/dev/null 2>&1; then
  SSH_MODE="alias"
  echo "  Connexion worker via alias SSH local: $WORKER_SSH_TARGET"
else
  SSH_MODE="proxyjump"
  echo "  Alias SSH indisponible, fallback via ProxyJump IP"
  if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "ubuntu@$MASTER_PUBLIC_IP" "echo ok" >/dev/null 2>&1; then
    echo "Erreur: impossible de joindre le master en SSH ($MASTER_PUBLIC_IP)." >&2
    echo "Vérifie la clé SSH, le SG du master (port 22), et l'IP source autorisée." >&2
    exit 1
  fi
fi

attempt=1
while [ "$attempt" -le "$MAX_RETRIES" ]; do
  if ssh_via_master "echo ok" >/dev/null 2>&1; then
    break
  fi
  echo "  Worker pas encore prêt (tentative $attempt/$MAX_RETRIES), retry dans ${RETRY_INTERVAL_SECONDS}s..."
  attempt=$((attempt + 1))
  sleep "$RETRY_INTERVAL_SECONDS"
done

if [ "$attempt" -gt "$MAX_RETRIES" ]; then
  echo "Erreur: worker injoignable en SSH apres $MAX_RETRIES tentatives." >&2
  echo "Mode de connexion utilisé: $SSH_MODE" >&2
  echo "Diagnostic master -> worker (port 22):" >&2
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "ubuntu@$MASTER_PUBLIC_IP" \
    "command -v nc >/dev/null 2>&1 && nc -vz -w 3 $WORKER_PRIVATE_IP 22 || timeout 3 bash -lc 'echo > /dev/tcp/$WORKER_PRIVATE_IP/22'" 2>&1 || true
  echo "Diagnostic SSH (verbose) via ProxyJump:" >&2
  ssh -vvv -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -J "ubuntu@$MASTER_PUBLIC_IP" "ubuntu@$WORKER_PRIVATE_IP" "echo ok" 2>&1 | tail -n 30 >&2 || true
  exit 1
fi

echo "  Worker SSH OK"

echo -e "${YELLOW}[3/5] Copie de la clé de déploiement sur le worker...${NC}"
scp_to_worker "$DEPLOY_KEY" "$TMP_REMOTE_KEY"
echo "  Clé copiée dans $TMP_REMOTE_KEY"

echo -e "${YELLOW}[4/5] Installation sécurisée pour l'utilisateur jenkins...${NC}"
ssh_via_master \
  "sudo install -d -m 700 -o jenkins -g jenkins /var/jenkins/.ssh && \
   sudo install -m 600 -o jenkins -g jenkins $TMP_REMOTE_KEY $WORKER_KEY_DEST && \
   sudo rm -f $TMP_REMOTE_KEY && \
   sudo ls -l $WORKER_KEY_DEST"

echo -e "${YELLOW}[5/5] Vérification de lecture par le user jenkins...${NC}"
ssh_via_master \
  "sudo -u jenkins test -r $WORKER_KEY_DEST && echo '  Lecture OK pour jenkins'"

echo
echo -e "${GREEN}=== Bootstrap worker terminé ===${NC}"
echo "Clé installée: $WORKER_KEY_DEST"

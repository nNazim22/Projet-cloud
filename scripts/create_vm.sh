#!/bin/bash
set -euo pipefail

VM_CLOUD="proxmox"
for arg in "$@"; do
  case "$arg" in
    cloud=*) VM_CLOUD="${arg#cloud=}" ;;
    name=*)  VM_NAME="${arg#name=}" ;;
    size=*)  VM_SIZE="${arg#size=}" ;;
    ip=*)    VM_IP="${arg#ip=}" ;;
  esac
done

# Validation : le client ne peut pas viser n'importe quoi
[[ "$VM_CLOUD" =~ ^(proxmox|aws)$ ]] || { echo "Cloud invalide (proxmox ou aws)"; exit 1; }
[[ "${VM_NAME:-}" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "Nom invalide (a-z, 0-9, tiret, 2 a 31 caracteres)"; exit 1; }
[[ "${VM_SIZE:-}" =~ ^(small|medium|large)$ ]] || { echo "Taille invalide (small, medium ou large)"; exit 1; }
if [ "$VM_CLOUD" = "aws" ] && [ "$VM_SIZE" = "large" ]; then
  echo "Taille large indisponible sur AWS (small ou medium)"; exit 1
fi
if [ "$VM_CLOUD" = "aws" ]; then
  # Le nom commence par u<id>- (id du client dans le portail) : l'id fixe le VPC du client
  [[ "$VM_NAME" =~ ^u([1-9][0-9]{0,2})- ]] || { echo "Nom AWS invalide : il doit commencer par u<id>- (exemple u3-web01)"; exit 1; }
  CLIENT_ID="${BASH_REMATCH[1]}"
  { [ "$CLIENT_ID" -le 255 ] && [ "$CLIENT_ID" -ne 42 ] && [ "$CLIENT_ID" -ne 43 ]; } || { echo "Identifiant client $CLIENT_ID impossible pour un VPC AWS (1 a 255, sauf 42 et 43)"; exit 1; }
fi
if [ "$VM_CLOUD" = "proxmox" ]; then
  [[ "${VM_IP:-}" =~ ^172\.16\.117\.(17[0-9])$ ]] || { echo "IP invalide : plage autorisee 172.16.117.170 a .179"; exit 1; }
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
START=$(date +%s)

echo "=== 1/2 Terraform ($VM_CLOUD) : creation de la VM $VM_NAME ($VM_SIZE) ==="
if [ "$VM_CLOUD" = "proxmox" ]; then
  mkdir -p /var/lib/semaphore/tfstate
  cd "$REPO_DIR/terraform"
  terraform init -input=false
  terraform workspace select -or-create "$VM_NAME"
  terraform apply -input=false -auto-approve \
    -var "vm_name=$VM_NAME" -var "vm_size=$VM_SIZE" -var "vm_ip=$VM_IP"
  TARGET_IP="$VM_IP"
  SSH_USER="debian"
else
  [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || { echo "ERREUR : identifiants AWS non recus"; exit 1; }
  [ -n "${TF_VAR_ssh_public_key:-}" ] || { echo "ERREUR : TF_VAR_ssh_public_key non recue"; exit 1; }
  MYIP="$(curl -s https://checkip.amazonaws.com || wget -qO- https://checkip.amazonaws.com)"
  MYIP="$(echo "$MYIP" | tr -d '[:space:]')"
  [[ "$MYIP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERREUR : adresse publique introuvable"; exit 1; }
  export TF_VAR_admin_cidr="$MYIP/32"
  echo "SSH autorise depuis : $TF_VAR_admin_cidr"
  INSTANCE_TYPE="t3.micro"
  if [ "$VM_SIZE" = "medium" ]; then INSTANCE_TYPE="t3.small"; fi

  # Reseau du client : un VPC par client, cree a sa premiere commande puis reutilise (etat separe de celui des VM)
  echo "--- Reseau du client u$CLIENT_ID : VPC bits-u$CLIENT_ID (10.$CLIENT_ID.0.0/16), cree s'il n'existe pas ---"
  mkdir -p /var/lib/semaphore/tfstate-aws-vpc
  cd "$REPO_DIR/aws-vpc"
  terraform init -input=false
  terraform workspace select -or-create "vpc-u$CLIENT_ID"
  terraform apply -input=false -auto-approve -lock-timeout=120s -var "client_id=$CLIENT_ID"

  echo "--- VM $VM_NAME dans le VPC du client ---"
  mkdir -p /var/lib/semaphore/tfstate-aws
  cd "$REPO_DIR/aws"
  terraform init -input=false
  terraform workspace select -or-create "$VM_NAME"
  terraform apply -input=false -auto-approve \
    -var "vm_name=$VM_NAME" -var "instance_type=$INSTANCE_TYPE" -var "client_id=$CLIENT_ID"
  TARGET_IP="$(terraform output -raw vm_ip_publique)"
  SSH_USER="admin"
fi
T_TF=$(( $(date +%s) - START ))
echo "Terraform termine en $T_TF secondes (IP : $TARGET_IP)"

echo "=== 2/2 Ansible : configuration de la VM ==="
for i in $(seq 1 36); do
  if nc -z -w3 "$TARGET_IP" 22; then break; fi
  sleep 5
done
INV="$(mktemp)"
printf '[vms]\n' > "$INV"
cd "$REPO_DIR/ansible"
ansible-playbook -i "$INV" configure_vm.yml -e "target_ip=$TARGET_IP" -e "target_user=$SSH_USER"
rm -f "$INV"

TOTAL=$(( $(date +%s) - START ))
echo "VM $VM_NAME ($VM_CLOUD, $VM_SIZE) creee et configuree sur $TARGET_IP en $TOTAL secondes (Terraform $T_TF s, Ansible $(( TOTAL - T_TF )) s)"

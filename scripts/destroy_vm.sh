#!/bin/bash
set -euo pipefail

VM_CLOUD="proxmox"
for arg in "$@"; do
  case "$arg" in
    cloud=*) VM_CLOUD="${arg#cloud=}" ;;
    name=*)  VM_NAME="${arg#name=}" ;;
  esac
done

[[ "$VM_CLOUD" =~ ^(proxmox|aws)$ ]] || { echo "Cloud invalide (proxmox ou aws)"; exit 1; }
[[ "${VM_NAME:-}" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "Nom invalide"; exit 1; }
[[ "$VM_NAME" != "default" ]] || { echo "Nom reserve"; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
START=$(date +%s)

if [ "$VM_CLOUD" = "proxmox" ]; then
  cd "$REPO_DIR/terraform"
  DESTROY_ARGS=(-var "vm_name=$VM_NAME" -var "vm_size=medium" -var "vm_ip=0.0.0.0")
else
  [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || { echo "ERREUR : identifiants AWS non recus"; exit 1; }
  # La suppression lit l'etat : ces deux valeurs ne servent qu'a satisfaire Terraform
  export TF_VAR_admin_cidr="127.0.0.1/32"
  export TF_VAR_ssh_public_key="${TF_VAR_ssh_public_key:-ssh-ed25519 AAAAsuppression}"
  cd "$REPO_DIR/aws"
  DESTROY_ARGS=(-var "vm_name=$VM_NAME")
fi

terraform init -input=false

# On ne supprime que les VM creees par le portail (un workspace par VM)
if ! terraform workspace list | sed 's/^[* ]*//' | grep -qx "$VM_NAME"; then
  echo "Aucune VM ($VM_CLOUD) creee par le portail ne porte le nom : $VM_NAME"
  echo "VM connues :"
  terraform workspace list | sed 's/^[* ]*//' | grep -v -x -e default -e '' || true
  exit 1
fi

terraform workspace select "$VM_NAME"
terraform destroy -input=false -auto-approve "${DESTROY_ARGS[@]}"
terraform workspace select default
terraform workspace delete "$VM_NAME"
echo "VM $VM_NAME ($VM_CLOUD) supprimee en $(( $(date +%s) - START )) secondes"

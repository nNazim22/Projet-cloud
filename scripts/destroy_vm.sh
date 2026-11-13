#!/bin/bash
set -euo pipefail

# Lecture du champ du formulaire : name=...
for arg in "$@"; do
  case "$arg" in
    name=*) VM_NAME="${arg#name=}" ;;
  esac
done

[[ "${VM_NAME:-}" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "Nom invalide"; exit 1; }
[[ "$VM_NAME" != "default" ]] || { echo "Nom reserve"; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
START=$(date +%s)
cd "$REPO_DIR/terraform"
terraform init -input=false

# On ne supprime que les VM creees par le portail (un workspace par VM)
if ! terraform workspace list | sed 's/^[* ]*//' | grep -qx "$VM_NAME"; then
  echo "Aucune VM creee par le portail ne porte le nom : $VM_NAME"
  echo "VM connues :"
  terraform workspace list | sed 's/^[* ]*//' | grep -v -x -e default -e '' || true
  exit 1
fi

terraform workspace select "$VM_NAME"
# Les valeurs size et ip ne servent pas a la suppression : elles sont lues dans l'etat
terraform destroy -input=false -auto-approve \
  -var "vm_name=$VM_NAME" -var "vm_size=medium" -var "vm_ip=0.0.0.0"

terraform workspace select default
terraform workspace delete "$VM_NAME"
echo "VM $VM_NAME supprimee en $(( $(date +%s) - START )) secondes"

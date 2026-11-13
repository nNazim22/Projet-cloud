#!/bin/bash
set -euo pipefail

# Lecture des champs du formulaire : name=... size=... ip=...
for arg in "$@"; do
  case "$arg" in
    name=*) VM_NAME="${arg#name=}" ;;
    size=*) VM_SIZE="${arg#size=}" ;;
    ip=*)   VM_IP="${arg#ip=}" ;;
  esac
done

# Validation : le client ne peut pas viser n'importe quoi
[[ "${VM_NAME:-}" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "Nom invalide (a-z, 0-9, tiret, 2 a 31 caracteres)"; exit 1; }
[[ "${VM_SIZE:-}" =~ ^(small|medium|large)$ ]] || { echo "Taille invalide (small, medium ou large)"; exit 1; }
[[ "${VM_IP:-}" =~ ^172\.16\.117\.(17[0-9])$ ]] || { echo "IP invalide : plage autorisee 172.16.117.170 a .179"; exit 1; }

cd "$(dirname "$0")/../terraform"
mkdir -p /var/lib/semaphore/tfstate
START=$(date +%s)
echo "Variables TF_VAR_ recues : $(env | grep -o '^TF_VAR_[A-Za-z_]*' | tr '\n' ' ')"

terraform init -input=false
terraform workspace select -or-create "$VM_NAME"
terraform apply -input=false -auto-approve \
  -var "vm_name=$VM_NAME" -var "vm_size=$VM_SIZE" -var "vm_ip=$VM_IP"

echo "VM $VM_NAME ($VM_SIZE) prete sur $VM_IP en $(( $(date +%s) - START )) secondes"

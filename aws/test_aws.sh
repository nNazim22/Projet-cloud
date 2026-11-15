#!/bin/bash
set -u -o pipefail
cd "$(dirname "$0")"

# --- Contrôles préalables ---
[ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || { echo "ERREUR : cles AWS absentes de la session (read -rs puis export)"; exit 1; }
grep -q 'resource "aws_instance"' main.tf || { echo "ERREUR : main.tf ne cree pas d'instance (version lecture seule)"; exit 1; }

export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
export TF_VAR_admin_cidr="$(curl -s https://checkip.amazonaws.com)/32"
echo "Adresse autorisee en SSH : $TF_VAR_admin_cidr"

# --- Nettoyage garanti, même en cas d'erreur ---
cleanup() {
  echo "=== Destruction ==="
  D0=$SECONDS
  terraform destroy -input=false -auto-approve | tail -3
  echo "Destruction : $((SECONDS - D0)) secondes"
  echo "Ressources restantes dans l'etat : $(terraform state list | wc -l)"
}
trap cleanup EXIT

terraform init -input=false > /dev/null || exit 1
terraform validate || exit 1
terraform plan -input=false | grep -E "^Plan:|Error"

# --- Création ---
echo "=== Creation ==="
C0=$SECONDS
terraform apply -input=false -auto-approve | tail -8
echo "Creation Terraform : $((SECONDS - C0)) secondes"

IP=$(terraform output -raw vm_ip_publique)
echo "IP publique : $IP"

# --- Attente du SSH, puis test des utilisateurs possibles ---
for i in $(seq 1 36); do nc -z -w3 "$IP" 22 && break; sleep 5; done
echo "Port 22 ouvert apres : $((SECONDS - C0)) secondes"

for U in admin debian; do
  if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$U@$IP" 'echo OK' 2>/dev/null | grep -q OK; then
    echo "UTILISATEUR SSH QUI FONCTIONNE : $U"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$U@$IP" 'hostname; head -2 /etc/os-release; nproc; free -h | grep Mem; df -h / | tail -1'
    break
  fi
done
echo "Duree jusqu'a une VM joignable : $((SECONDS - C0)) secondes"

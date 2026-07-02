#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${PROJECT_ROOT}/out"
KEY_NAME="${KEY_NAME:-kubeadm-gateway_ed25519}"
KEY_PATH="${OUT_DIR}/${KEY_NAME}"

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}"

if [[ -e "${KEY_PATH}" || -e "${KEY_PATH}.pub" ]]; then
  echo "SSH key already exists:"
  echo "  ${KEY_PATH}"
  echo "  ${KEY_PATH}.pub"
  echo
  echo "Refusing to overwrite. Delete them manually or set KEY_NAME to create a different key."
  exit 1
fi

ssh-keygen -t ed25519 -f "${KEY_PATH}" -N "" -C "kubeadm-gateway-takehome"

chmod 600 "${KEY_PATH}"
chmod 644 "${KEY_PATH}.pub"

cat <<EOF

Created SSH key pair:
  private: ${KEY_PATH}
  public:  ${KEY_PATH}.pub

Use this in terraform/terraform.tfvars:

ssh_public_key_path = "../out/${KEY_NAME}.pub"

Use this with Ansible/SSH:

ssh -i "${KEY_PATH}" ubuntu@<node-public-ip>
ansible-playbook -i out/inventory.ini ansible/site.yml --private-key "out/${KEY_NAME}"
EOF

#!/usr/bin/env bash

echo "Generating keypair......"
./scripts/generate-ssh-key.sh

echo "Running terraform to create infra...."
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
terraform -chdir=terraform output -raw ansible_inventory > ansible/inventory.ini

echo "Running ansible to set up core services....."
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$PWD/ansible/roles"

ansible-playbook \
  -i ansible/inventory.ini \
  ansible/site.yml \
  --private-key out/kubeadm-gateway_ed25519

echo "Deploying core kubernetes services...."
export KUBECONFIG="$PWD/out/admin.conf"
./scripts/core-services-installer.sh

echo "Deploying Argo apps...."
kubectl apply -f argoapps/cert-manager.yaml
kubectl apply -f argoapps/traefik.yaml

echo "Generating a dev user...."
# make sure .kube dir exists
mkdir -p "$HOME/.kube"

if command -v go >/dev/null 2>&1; then
    ./scripts/install-kcgen.sh
    ./out/bin/kcgen nginx-deployer
elif command -v openssl >/dev/null 2>&1; then
    ./scripts/kcgen-fallback.sh
else
  echo "error: neither go nor openssl found" >&2
  exit 1
fi

echo "setting up rbac for the new user...."
kubectl apply -f rbac/nginx-deployer.yaml

echo "environment is installed!"
echo "admin kubeconfig and ssh keys are in the 'out' directory"
echo "user kubeconfig will exist at $HOME/.kube/nginx-deployer-kubeconfig.yaml"

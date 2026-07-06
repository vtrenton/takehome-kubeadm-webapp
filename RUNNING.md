# Running

Follow each section step-by-step to build the demo environments

Note: please make sure to run these commands at the project root!

## Important: Prerequisites!
```
AWS account/awscli configured (demo on ec2)
Terraform/OpenTofu (both work and tested)
ansible
kubectl
helm
go (or openssl)
bash (I haven't tested these scripts with zsh or POSIX shells)
```
This should work with the latest version of all of this software.

## Node SSH keys
Keypair will be output to the "out/" directory
```bash
./scripts/generate-ssh-key.sh
```

## Terraform
This will set up three ec2 nodes, a vpc, subnet, network policies, internet gateway, and an NLB
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
terraform -chdir=terraform output -raw ansible_inventory > ansible/inventory.ini
```

## Ansible
This will configure each of the nodes for kubernetes by installing the correct packages, systctls and finally install kubernetes via kubeadm
```bash
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$PWD/ansible/roles"

ansible-playbook \
  -i ansible/inventory.ini \
  ansible/site.yml \
  --private-key out/kubeadm-gateway_ed25519
```

## Core k8s services
Kubernetes will be up and running at this point but missing important core services such as the CNI, metrics-server and gateway-api CRDs (these are important later).
```bash
# set the admin kubeconfig
export KUBECONFIG="$PWD/out/admin.conf"

./scripts/core-services-installer.sh
```

## Argo Apps
We should use argo to deploy apps going forward from this point. Such as our ingress/gateway-api controller "Traefik".
```bash
kubectl apply -f argoapps/cert-manager.yaml
kubectl apply -f argoapps/traefik.yaml
```

## "User" Creation
For this step I created a small go program to do the dirty work.
You can see the Source code for it here:

https://github.com/vtrenton/kcgen

All the code is just in the main.go and I made sure to comment each section so it's easy to follow the process.

There is a script to install and run this program to create a csr, approve it and generate a kubeconfig
```bash
./scripts/install-kcgen.sh

# if for whatever reason ~/.kube hasn't been created on your machine this program will need it.
mkdir -p "$HOME/.kube"

./out/bin/kcgen nginx-deployer
```

If you cannot use go for whatever reason I added a fallback shell script that uses openssl. So please make sure openssl is installed.

./scripts/kcgen-fallback.sh

## RBAC Creation
Create the user/developer namespace and set up a role/rolebinding leveraging the principal of least priveleged. Note that roles (and in turn rolebindings) are namespaced meaning they will only apply to the namespace specified.
```
kubectl apply -f rbac/nginx-deployer.yaml
```





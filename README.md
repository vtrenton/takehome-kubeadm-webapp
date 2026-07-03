# kubeadm Gateway take-home

This repository builds a kubeadm-based Kubernetes cluster on AWS EC2.

The project intentionally separates infrastructure provisioning, kubeadm bootstrap, and platform/application installation:

- Terraform provisions AWS infrastructure.
- Ansible installs and initializes Kubernetes with kubeadm.
- A shell installer deploys the core cluster services: Cilium, Gateway API CRDs, metrics-server, and Argo CD.
- Argo CD will later manage platform/application resources through Kubernetes `Application` CRDs.

## Terraform scope

Terraform owns:

- VPC, public subnets, route table, internet gateway
- EC2 key pair
- one control-plane EC2 instance
- two worker EC2 instances by default
- security groups for common node traffic, control-plane API access, and worker edge traffic
- public AWS Network Load Balancer
- TCP 80/443 listeners
- target group attachments to worker instances only
- generated Ansible inventory output

Terraform intentionally does **not** install Kubernetes. Ansible consumes the generated inventory and runs the kubeadm bootstrap flow.

## Ansible scope

Ansible owns the kubeadm node/bootstrap flow:

- install base OS packages
- disable swap
- configure required kernel modules and sysctls
- install and configure containerd
- install `kubeadm`, `kubelet`, and `kubectl`
- run `kubeadm init` on the control-plane node
- join worker nodes with `kubeadm join`
- fetch the admin kubeconfig to `out/admin.conf`

Ansible intentionally does **not** install Cilium, Gateway API CRDs, Argo CD, Traefik, cert-manager, or the Nginx application.

## Core services scope

The core services installer owns the first post-kubeadm services:

- Cilium as the CNI
- Gateway API CRDs for `GatewayClass`, `Gateway`, `HTTPRoute`, and related Gateway API resources
- metrics-server for Kubernetes resource metrics
- Argo CD as the GitOps controller

Gateway API CRDs are installed here instead of through Argo CD so Traefik can be deployed later without relying on asynchronous CRD ordering. Traefik's Gateway API provider expects the Gateway API CRDs to already exist.

The installer intentionally keeps Helm chart configuration in project values files instead of embedding inline YAML in the script.

Expected files:

```text
scripts/core-services-installer.sh
values/cilium.yaml
values/metrics-server.yaml
values/argocd.yaml
```

The script installs Gateway API CRDs directly with `kubectl apply --server-side` from the upstream Gateway API standard install manifest.

## First run

Generate a project-local SSH key. This writes keys into `out/` and does not touch `~/.ssh`.

```bash
./scripts/generate-ssh-key.sh
```

Provision AWS infrastructure:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt -recursive
terraform validate
terraform apply

terraform output -raw ansible_inventory > ../ansible/inventory.ini
cd ..
```

Validate Ansible connectivity:

```bash
ansible -i ansible/inventory.ini all \
  -m ping \
  --private-key out/kubeadm-gateway_ed25519 \
  --ssh-common-args="-o StrictHostKeyChecking=accept-new"
```

Run the kubeadm bootstrap playbook:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/site.yml \
  --private-key out/kubeadm-gateway_ed25519
```

Use the generated kubeconfig:

```bash
export KUBECONFIG=out/admin.conf
kubectl get nodes
```

At this point the nodes are expected to be `NotReady` until the CNI is installed.

Example:

```text
NAME             STATUS     ROLES           AGE     VERSION
ip-10-50-1-159   NotReady   <none>          2m33s   v1.36.2
ip-10-50-1-5     NotReady   control-plane   3m21s   v1.36.2
ip-10-50-2-219   NotReady   <none>          2m33s   v1.36.2
```

## Install core services

Run the core services installer:

```bash
./scripts/core-services-installer.sh
```

The script uses the project kubeconfig at:

```text
out/admin.conf
```

It can be run from the project root or from inside the `scripts/` directory.

The installer performs these steps:

```text
1. Install Cilium
2. Wait for nodes and CoreDNS to become ready
3. Install Gateway API CRDs
4. Install metrics-server
5. Install Argo CD
```

After the installer completes, verify the cluster:

```bash
export KUBECONFIG=out/admin.conf

kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes
```

Verify the Gateway API CRDs:

```bash
kubectl get crd gatewayclasses.gateway.networking.k8s.io
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io
```

The nodes should now be `Ready` after Cilium is healthy.

Argo CD is installed as the GitOps controller, but this demo does not require using the Argo CD UI. Later phases will create Argo CD `Application` resources directly with `kubectl`.

## Next platform phase

After core services are installed, Argo CD can manage the remaining platform components.

Expected next files:

```text
argoapps/cert-manager.yaml
argoapps/traefik.yaml

values/cert-manager.yaml
values/traefik.yaml
```

Apply the Argo CD applications with:

```bash
kubectl apply -f argoapps/
```

Gateway API CRDs are not represented as an Argo CD application in this repository because they are installed during core bootstrap before Traefik.

## Design notes

The public NLB forwards TCP 80/443 directly to the worker EC2 instances. Traefik will later run on worker nodes and bind 80/443, allowing TLS termination inside Kubernetes via Gateway API and cert-manager.

The control-plane node is not registered in the NLB target groups.

The security group model is intentionally split:

- common node security group: SSH, unrestricted private node-to-node traffic, outbound internet
- control-plane API security group: Kubernetes API port 6443
- worker edge security group: HTTP/HTTPS ports 80/443

For challenge/reviewer convenience, SSH and Kubernetes API access may be opened broadly in `terraform.tfvars`. This is not a production security posture. A production deployment should restrict SSH/API access to trusted operator CIDRs, a bastion, VPN, or AWS Systems Manager Session Manager.

The core services installer intentionally uses the latest chart versions from each Helm repository for low-friction challenge deployment. Production usage should pin chart versions for repeatability. The Gateway API CRD install URL should also be pinned for repeatability.

## Local output directory

Project-generated local files live under `out/`, including generated SSH keys, kubeconfigs, rendered inventories, and temporary cert material.

Terraform reads the generated SSH public key by default from `../out/kubeadm-gateway_ed25519.pub`, relative to the `terraform/` directory. This keeps the checkout portable across machines and paths.

The entire `out/` directory is ignored by Git so generated credentials are not accidentally committed.

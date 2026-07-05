# kubeadm webapp take-home

This repository builds a kubeadm-based Kubernetes cluster on AWS EC2 and deploys a small platform stack for exposing an Nginx application.

The project is intentionally split into simple phases:

- Terraform provisions AWS infrastructure.
- Ansible bootstraps Kubernetes with kubeadm.
- A core services script installs the first cluster services.
- Argo CD `Application` resources install platform add-ons.
- `kcgen`, a small Go utility, automates the Kubernetes CSR/client-certificate kubeconfig flow.
- RBAC grants the generated user limited permissions for manual application deployment.
- A Helm chart will deploy the Nginx application through either traditional Ingress or Gateway API.
- Argo CD will deploy the same application through an `Application` resource for the GitOps path.

## Current architecture

```text
Internet
  |
  v
AWS Network Load Balancer
  TCP 80/443
  |
  v
Worker EC2 nodes
  hostPort 80/443
  |
  v
Traefik DaemonSet
  |
  v
Kubernetes Services / Nginx application
```

The NLB forwards TCP 80/443 to worker nodes. Traefik runs as a DaemonSet on the workers and exposes `hostPort` 80/443. Traefik is configured to support both traditional Kubernetes `Ingress` and Gateway API resources.

Before any application routes exist, a request to the NLB should return Traefik's default 404 response. That is an expected validation checkpoint.

## Repository layout

```text
.
├── ansible/
├── argoapps/
│   ├── cert-manager.yaml
│   └── traefik.yaml
├── rbac/
│   └── nginx-deployer.yaml
├── scripts/
│   ├── core-services-installer.sh
│   ├── generate-ssh-key.sh
│   ├── install-kcgen.sh
│   └── kcgen-fallback.sh
├── terraform/
├── values/
│   ├── argocd.yaml
│   ├── cert-manager.yaml
│   ├── cilium.yaml
│   ├── metrics-server.yaml
│   └── traefik.yaml
└── out/                 # generated locally; ignored by Git
```

The eventual application phase will add:

```text
charts/
  nginx-webapp/

argoapps/
  nginx-gitops.yaml
```

## Terraform scope

Terraform owns the AWS infrastructure:

- VPC and public subnets
- internet gateway and route table
- EC2 key pair
- one control-plane EC2 instance
- two worker EC2 instances by default
- common node security group
- control-plane API security group
- worker edge security group
- public AWS Network Load Balancer
- TCP 80/443 NLB listeners
- NLB target group attachments to worker instances only
- generated Ansible inventory output

Terraform intentionally does **not** install Kubernetes.

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
- Gateway API CRDs
- metrics-server
- Argo CD

The script intentionally uses the latest chart versions from the configured upstream Helm repositories. For this take-home, the important reproducibility requirement is install order.

Cilium must be installed with hostPort support before Traefik is deployed. Traefik uses `hostPort` 80/443, and those rules are created when the pod sandbox is created.

`values/cilium.yaml` should include:

```yaml
kubeProxyReplacement: false

cni:
  chainingMode: portmap

ipam:
  mode: cluster-pool
  operator:
    clusterPoolIPv4PodCIDRList:
      - 10.244.0.0/16
    clusterPoolIPv4MaskSize: 24
```

Gateway API CRDs are installed in the core services script instead of Argo CD so Traefik can be deployed later without depending on asynchronous CRD ordering.

## Platform applications

Argo CD platform applications live in:

```text
argoapps/
  cert-manager.yaml
  traefik.yaml
```

They are installed with:

```bash
kubectl apply -f argoapps/
```

This repo keeps the Argo CD setup intentionally simple. It does not use an App-of-Apps pattern yet. The small set of platform `Application` resources can be applied directly after Argo CD is installed.

### cert-manager

cert-manager is installed by Argo CD from the upstream chart.

It is used later to issue TLS certificates for the Nginx application.

### Traefik

Traefik is installed by Argo CD from the upstream chart.

Traefik is configured to:

- run as a DaemonSet
- use `hostPort` 80/443
- install a default `IngressClass`
- enable the Kubernetes Ingress provider
- enable the Kubernetes Gateway provider
- create a GatewayClass/Gateway through the chart

The eventual Nginx Helm chart will support both exposure modes:

```text
route.type=ingress
route.type=gateway
```

Ingress is the simple/default path. Gateway API is included to demonstrate knowledge of the newer API without making the whole assessment depend on it.

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

## Install core services

Run:

```bash
./scripts/core-services-installer.sh
```

The script uses:

```text
out/admin.conf
```

It can be run from the project root or from inside the `scripts/` directory.

The installer performs these steps:

```text
1. Install Cilium with portmap chaining enabled
2. Wait for nodes and CoreDNS to become ready
3. Install Gateway API CRDs
4. Install metrics-server
5. Install Argo CD
```

Verify the cluster:

```bash
export KUBECONFIG=out/admin.conf

kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes
```

Verify Gateway API CRDs:

```bash
kubectl get crd gatewayclasses.gateway.networking.k8s.io
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io
```

## Install platform applications

Apply the Argo CD applications:

```bash
kubectl apply -f argoapps/
```

Check application state:

```bash
kubectl -n argocd get applications
```

Validate cert-manager:

```bash
kubectl -n cert-manager get pods
```

Validate Traefik:

```bash
kubectl -n traefik get pods -o wide
kubectl -n traefik rollout status daemonset/traefik --timeout=5m

kubectl get ingressclass
kubectl get gatewayclass
kubectl -n traefik get gateway
```

## Validate the edge path

After Traefik is installed, the NLB should reach Traefik even before any application route exists.

Get the NLB DNS name from Terraform:

```bash
terraform -chdir=terraform output
```

Then curl the NLB endpoint:

```bash
curl -i http://<nlb-dns-name>
```

Expected result before the Nginx app is deployed:

```text
HTTP/1.1 404 Not Found

404 page not found
```

That 404 is a success condition. It proves:

- the NLB DNS resolves
- the NLB listener is reachable
- the NLB target groups can reach worker nodes
- worker security group rules allow edge traffic
- Cilium hostPort/portmap is working
- Traefik is reachable from outside the cluster
- no application route exists yet

## Important hostPort note

If Cilium was first installed without `cni.chainingMode: portmap`, any existing Traefik pods must be recreated after fixing Cilium. HostPort NAT rules are created when the pod sandbox is created; changing Cilium later does not retroactively add hostPort rules to already-running pods.

For a clean run of this repo, this should not be necessary because the install order is:

```text
Cilium with portmap -> Argo CD -> Traefik
```

If troubleshooting an existing cluster, recreate Traefik pods with:

```bash
kubectl -n traefik delete pod -l app.kubernetes.io/name=traefik
kubectl -n traefik rollout status daemonset/traefik --timeout=5m
```

A useful smoke test for hostPort is:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: hostport-smoke
  namespace: default
spec:
  selector:
    matchLabels:
      app: hostport-smoke
  template:
    metadata:
      labels:
        app: hostport-smoke
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - name: http
              containerPort: 80
              hostPort: 18080
              protocol: TCP
EOF

kubectl rollout status daemonset/hostport-smoke --timeout=3m
```

Then test from the worker nodes:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible -i ansible/inventory.ini workers \
  -m shell \
  -a 'NODE_IP=$(hostname -I | awk "{print \$1}"); echo "Testing $NODE_IP:18080"; curl -i --max-time 3 http://$NODE_IP:18080 || true' \
  --private-key out/kubeadm-gateway_ed25519
```

Clean it up after testing:

```bash
kubectl delete daemonset hostport-smoke
```

## Argo CD UI

Argo CD is installed as the GitOps controller, but this demo does not require using the Argo CD UI. The repo uses Argo CD `Application` resources applied directly with `kubectl`.

## Kubernetes CSR user flow with kcgen

This project uses [`kcgen`](https://github.com/vtrenton/kcgen) to demonstrate the Kubernetes CertificateSigningRequest client-certificate flow while also showing Go/Kubernetes programming work.

`kcgen` generates a private key and CSR, uses the Kubernetes CSR API, and outputs a kubeconfig for the requested username.

Source code:

```text
https://github.com/vtrenton/kcgen
```

The binary is not committed to this repository. It is built locally into `out/bin/`.

Install the tool:

```bash
./scripts/install-kcgen.sh
```

Generate a kubeconfig for the application deployer user. This step uses the admin kubeconfig because the CSR must be submitted and approved before the generated user can authenticate.

```bash
export KUBECONFIG=out/admin.conf
./out/bin/kcgen nginx-deployer
```

`kcgen` writes the generated kubeconfig under the user's kubeconfig directory. Use the path printed by `kcgen`. For example:

```bash
export KUBECONFIG="$HOME/.kube/nginx-deployer-kubeconfig.yaml"
```

### CSR fallback path

The Go implementation is the preferred path because it demonstrates Kubernetes API programming. A shell fallback is also included in case the Go tool cannot be built or run in the reviewer environment.

Use the fallback only if the primary `kcgen` path fails:

```bash
export KUBECONFIG=out/admin.conf
./scripts/kcgen-fallback.sh nginx-deployer
```

The fallback script follows the same intended flow:

```text
generate private key -> generate CSR -> submit Kubernetes CertificateSigningRequest -> approve CSR -> fetch signed certificate -> build kubeconfig
```

Use the kubeconfig path printed by the fallback script. The rest of the RBAC validation flow is the same.

At this point the user should authenticate with a valid client certificate but should not be authorized to do application work yet.

Before RBAC, verify that the user has no useful permissions:

```bash
kubectl auth can-i create deployments -n nginx-manual
kubectl auth can-i get pods -n nginx-manual
kubectl auth can-i get nodes
```

Expected result:

```text
no
no
no
```

This confirms the certificate-authenticated user exists, but authorization is still controlled by RBAC.

## Apply RBAC for the generated user

Apply RBAC with the admin kubeconfig:

```bash
export KUBECONFIG=out/admin.conf
kubectl apply -f rbac/nginx-deployer.yaml
```

The RBAC should create the target namespace and bind the `nginx-deployer` user to a namespace-scoped app deployer role.

Switch back to the generated user kubeconfig:

```bash
export KUBECONFIG="$HOME/.kube/nginx-deployer-kubeconfig.yaml"
```

Verify the intended permissions:

```bash
kubectl auth can-i create deployments -n nginx-manual
kubectl auth can-i create services -n nginx-manual
kubectl auth can-i create ingresses -n nginx-manual
kubectl auth can-i create httproutes.gateway.networking.k8s.io -n nginx-manual
kubectl auth can-i get nodes
kubectl auth can-i approve certificatesigningrequests.certificates.k8s.io
```

Expected result:

```text
yes
yes
yes
yes
no
no
```

The user should be able to deploy the Nginx application in the intended namespace, but should not have cluster-admin access.

## Expected RBAC shape

The RBAC file should look roughly like this:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nginx-manual
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-deployer
  namespace: nginx-manual
rules:
  - apiGroups: [""]
    resources:
      - configmaps
      - services
      - pods
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  - apiGroups: ["gateway.networking.k8s.io"]
    resources:
      - httproutes
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  - apiGroups: ["cert-manager.io"]
    resources:
      - certificates
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nginx-deployer-app-deployer
  namespace: nginx-manual
subjects:
  - kind: User
    name: nginx-deployer
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: app-deployer
  apiGroup: rbac.authorization.k8s.io
```

The app chart may not need every permission above immediately, but this role keeps access namespace-scoped and avoids cluster-admin privileges.

## Remaining work

The cluster/platform and CSR/RBAC flow are now mostly complete.

Remaining implementation areas:

```text
1. Nginx application Helm chart
2. Ingress/Gateway route toggle in the chart
3. Manual app deployment using the CSR-created kubeconfig
4. GitOps app deployment using Argo CD
5. cert-manager issuer and TLS validation
6. final design notes and handoff validation steps
```

## Application deployment plan

The final application phase should prove two things:

```text
Manual path:
  nginx-deployer kubeconfig -> Helm install/upgrade -> Nginx app reachable through Traefik

GitOps path:
  Argo CD Application -> same chart -> second Nginx app deployment
```

The application chart should support:

```text
route.type=ingress
route.type=gateway
```

Suggested namespaces:

```text
nginx-manual
nginx-gitops
```

The manual deployment should use the CSR-generated kubeconfig:

```bash
export KUBECONFIG="$HOME/.kube/nginx-deployer-kubeconfig.yaml"

helm upgrade --install nginx-manual ./charts/nginx-webapp \
  --namespace nginx-manual \
  --values values/nginx-manual.yaml
```

The GitOps deployment should use an Argo CD `Application` resource:

```bash
export KUBECONFIG=out/admin.conf
kubectl apply -f argoapps/nginx-gitops.yaml
```

## Local output directory

Project-generated local files live under `out/`, including generated SSH keys, kubeconfigs, rendered inventories, built local tools, and temporary cert material.

The preferred CSR helper is the Go-based `kcgen` binary built into `out/bin/`. The `scripts/kcgen-fallback.sh` script is committed as a backup path and does not require committing the generated `kcgen` binary.

Terraform reads the generated SSH public key by default from `../out/kubeadm-gateway_ed25519.pub`, relative to the `terraform/` directory. This keeps the checkout portable across machines and paths.

The entire `out/` directory is ignored by Git so generated credentials and local binaries are not accidentally committed.

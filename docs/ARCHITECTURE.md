# Architecture Design Choices and Decisions.

In this document I hope to show the current architecture as it's laid out by this repo. I will go over some of the choices I made and why for each part.

[<img src="../assets/architecture.png" alt="Infrastructure Diagram" width="500">](../assets/architecture.png)
## Infrastructure automation and Seperation of Concerns
In this project I used a few different automation tools to accomplish the goals. Each tool has a clear defnition of the area that it excels in. Below I hope to show why I chose the tools I did for the given task as well as what the tool is doing for the greater project.

### Terraform - Infrastructure provisoning and lifecycle
Terraform is a great tool for managing state and has a robust ecosystem for quickly provisioning state in a declarative manner. For this reason it's a great tool for spinning up nodes with images on them, Node network architecture, loadbalancers, DNS and other auxilary services.

**With this project I used Terraform to provison the following resources:**
```
-> ec2 machines with prebuilt Amazon AMIs
-> Installed ssh keypair for admin access to the nodes (and ansible)
-> A VPC to put our Infrastructure in a private network space
-> Two subnets for cross AZ worker nodes and private east to west cluster traffic.
-> A simple Network (Layer 4) LoadBalancer to connect to the two worker nodes on their application ports
-> Network policies that allow access to the ingress endpoint and kubernetes API endpoints
```
While I did make sure basic security was accounted for here there a few areas I could have potentially tightened up. A lot of these cases the additional complexity of management just wasn't worth the tradeoff:
```
-> Hardened AMI images could have been used. I didn't patch the system or check for vulnerabilities. This is small but I feel something like this is where a declarative or "cloud-native" immutable OS will shine.
-> Open east <-> west traffic between nodes. while I could have restricted this to known ports between the nodes there are better and more kubernetes native patterns for this such as Ciliums "Host Network Policies" which are much more portable for hybrid installs.
-> tighter access to Kube-API. Kubernetes secures it's API with mTLS which is pretty strong and depending on the algorithm used is going to be like breaking https. That said for long running infrastructure there is stilla risk of exploits on publically exposed administration services. So depending on the lifecycle of this environment it would be wise to maybe use a Jumphost or even Teleport to avoid accessing it outside of internal endpoints.
-> Restricting SSH. Much like the Kube-API SSH is protected by strong cryptography making public exposure a potential risk. This is where Teleport or a Bastion comes in handy
```

With Security being a tradeoff between complexity cost and Defense I feel I provided the most practical defaults for the request.

***Why the LB?***
One of the requirements was to have more than a single worker node. Putting a LoadBalancer in front of the nodes was a low cost way of creating HA for the applications.

### Ansible - Machine configuration
Ansible is a powerful configuration management engine that allows for declarative automation against many machines. Terraform has some tools for machine management but I feel Ansible has a much stronger story here.

Having ansible is also very useful as it allows us to collectively troubleshoot and configure all the nodes to keep them uniform going forward.

For example I can run several commands on every node for troubleshoot!
```bash
# All the nodes
ANSIBLE_CONFIG=ansible/ansible.cfg ansible -i ansible/inventory.ini all\
  -m shell \
  -a 'ping -c1 google.com' \
  --private-key out/kubeadm-gateway_ed25519

# Or test the ingress on the workers!
ANSIBLE_CONFIG=ansible/ansible.cfg ansible -i ansible/inventory.ini workers\
  -m shell \
  -a 'curl -k -I -H "Host: webapp.local" https://localhost' \
  --private-key out/kubeadm-gateway_ed25519
```

With the core infrastructure set up we will have access to some bare bones linux nodes. We need to provision them with kubeadm to create a kubernetes cluster. This Ansible code sets up the machines as per install requirements of the [official kubernetes installation guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/).

This ansible script will do the following:
```
-> disable swap on all the nodes
-> assure the proper kernel modules are loaded (onverlay, br_netfilter)
-> Set important sysctls for bridging and overlay.
-> install base packages.
-> install containerd
-> configure containerd to utilized systemd cgroups.
-> install the kubelet (and addtional kubernetes packages)
-> Uses kubeadm to initialize the control-plane with the latest version of k8s (currently 1.36)
-> captures the join command for the workers
-> builds an admin kubeconfig and sets the endpoint to the public ec2 address
-> joins the workers to the kubeadm deployed cluster
```

***Note: It's worth mentioning that technically nodes can be run with*** [swap activated](https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/).

I choose to disable swap to reduce risk and complexity of management in this case.

**A worthwhile security note:** I have ansible auto-accepting ssh keys for the newly provisoned node. This is because you probably haven't sshed into these hosts before and ansible itself is non-interactive.

Normally it may not be the best method to do this depending on internal threat models as we should validate ssh keys to reduce the risk of a Man-in-the-Middle Attack. But in this case it works and our nodes are short lived so the risk is minimal.

**A worthwhile Infrastructure note:** Another kubernetes deployment method we could have used is the "three nodes all roles" strategy.

Currently, our kubernetes control-plane is on a single node so it is not HA. If this node goes offline so does all of our cluster access and management. This is risky and not advised in production deployments.

Another model for 3 nodes would be to allow scheduling onto the control plane and have all three nodes run as control-plane AND workers. It's generally not advised to run workloads on the same nodes as etcd specifically as etcd is very latency sensative around networking and i/o heartbeats. For a small web app workload the tradeoff is negliable.

### Core Workloads - Foundational cluster applications.
Ansible will leave us with a working cluster in the sense of being able to access certain resources but the nodes will show as "Not Ready" due to the lack of networking. This script will deploy the following resources:
```
-> Cilium CNI (With Hubble but not exposed)
-> Metrics server
-> Gateway-API CRDs
-> ArgoCD
```

We need a CNI in order to facilitate cross-node pod-pod networking which is why kubernetes will be stuck in a not ready state before this. The job of the Container Network Interface (CNI) is to create a L2 Overlay LAN in which the pods can share (normally something like VXLAN) across nodes (this is why those kernel modules and sysconfig settings from the ansible step are important btw).

I chose Cilium as it's currently the only graduated CNI in the [CNCF landscape](https://landscape.cncf.io/?group=projects-and-products&project=graduated). While this in itself says nothing about the readiness of production itself it does mean the project has strong vendor agnostic suppport. The risk of upstream "rug-pulling" is much lower than that of other CNI's. It also provides a lot of additional features that I could use for networking in the future (such as a L2 gARP broadcaster to replace MetalLB for On-prem deployments) or even it's own gateway-api implementations.

Hubble is installed by default. it's not exposed but can be pretty easily. It can be helpful troubleshooting tool in the future so i'm not going to bother ommiting it from the install.

Next up is the metrics server. I like to make a habbit of installing this right away as it is mostly set-it and forget it. It can come in very handy for minimal troubleshooting such as `kubectl top pods` or `kubectl top nodes`. It can also come in handy when Observablilty frameworks make their way into the picture.

Next is the Gateway-API CRDs. I explain it more below but Gateway-API is the future so installing these lightweight CRDs is a small toll for future-proofing the cluster design.

Finally we install ArgoCD. Argo is going to help us stop doing hands on administration of the cluster and start leveraging GitOps with upstream git repos as our source of truth. Reducing the number of hands on the cluster and making infrastructure declarative is the best way to reduce the risks accoiated with multi-tenant kubernetes deployments.

### Argo Apps - The GitOps Managed Application Deployments
From this point forward it is optimal to manage deployments and lifecycle of everything via ArgoCD "Applications". This allows us to move off the cluster and into a more developer familiar ecosystem - git!

For a production deployment I would normally leverage the [App-of-Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern-alternative) pattern that involves having a single repo that Argo watches with "Application" deployments. When updated Argo will install the Application which will instruct Argo to install the application referenced by the "Application" CRD.

The core applications that Argo will install are:
```
Cert-Manager
Traefik
```

Traefik notably will be deployed in HostPort Node. This means that each of the machines that it is deployed on (Not the control-plane) will set up a listener on 80/443. In the Terraform step we already configured a layer 4 loadbalancer to front the worker nodes here so we should be able to hit the loadbalancer and successfully get a 404 response from Traefik.

***Note about Cilium:***
It's worth noting that using cilium without KPR (Kube-Proxy Replacement) requires an additional tool to manage HostPort Deployment for this reason Cilium needs to be deployed with `cni.chainingMode=portmap`. which leverages the Cilium "portmap" plugin for publishing node ports.

***Note about Gateway-api:***
Externally, I can hit gateway-api using the published web/websecure ports. But Gateway Objects need to hit the trafik pod on it's "gateway" ports which are `8000` for `web` and `8443` for `websecure` respectively.


## Kubernetes Architecture

[<img src="../assets/kubernetes-diagram.png" alt="k8s Diagram" width="500">](../assets/kubernetes-diagram.png)

### Cluster layout
The Kubernetes cluster itself is on top of 1 control-plane node and two worker nodes. Having two worker nodes means an application that is deployed with >1 replica can portentially leverage high availability.

### Cluster Networking
The Cluster itself is using kube-proxy in the default iptables mode. There are clear avantages to nftables mode such as O(1) (constant resource scaling) vs O(n) (linear) resource scaling. This would be high on my list to swap out if this cluster were to grow past the point of a simple webapp. But I left it at iptables mode and no Cilium KPR for simplicity.

### Cluster Storage
No applications require storage in this cluster so no CSI provider was installed

### Backup/Recovery
The cluster itself is stateless and declarative top to bottom which means we can leverage the GitOps pattern and keep this cluster idepotent and agile. Because of this there is no actual need for a formal backup solution to store "state" of any kind.

### Auditing
To save disk space on the cheap root volumes I choose not to enable Kubernetes Audit logging. But Kubernetes Audit logging is an incredibly powerful troubleshooting tool as it can be used to review request/response to the API server. This is not only useful for Security but for troubleshooting rouge automation as well. This is something a production cluster would likely have.

### User Access
Described in more detail in the [RBAC](RBAC.md) Documentation. But Follows standard practice of principal of least priveleged and explicate permissions.

### Ingress
Traefik was chosen as the L7 gateway/ingress for  this cluster and runs as the HostPort on each worker node. The external l4 loadbalancer handles backend requests to these endpoints. More reasoning for this decision is discussed below.

### GitOps
ArgoCD was chosen as the Application to facilitate the GitOps patterns for deployments. ArgoCD is an incredilby popular CNCF Graduated tool for facilitate repository syncronization.

## Odd-balls or "why did you include that?"
From this point forward it's all about Application Deployments. I want to take the opportuninty to explain the Why in specifically two areas that withou context may not make much sense in why I took the approach I did

### kcgen - the go program
For the process of generating the "user" kubeconfig it took a non-standard approach that I might not actually leverage in a real production environment.

***Namely, I built a go program to do it.***

The Source for this program can be found [here](https://github.com/vtrenton/kcgen)

***Why?***
While this may be uncanny there are a few reasons I did this:
```
Fun/Challenge -> I was getting sick of writting shell scripts and wanted to show a different approach.
Clean automation -> go is a very self contained langauge where everything is statically linked so I'm fairly certain go binaries will work very well and wont rely on the environment.
Compentancy in go -> I wanted the opportuninty to show off my go/kubernetes automation skillset.
Personal Project -> I actually have been planning to build this out into an operator (kubebuilder) in the future. This project helped me build out some seperation of concerns.
```

It's worth noteing I did write a fallback script in scripts/fallback-kcgen.sh. That uses a script to automate it. So the go binary isn't "required" just fun/nice to have.

This binary does the following
```
-> Takes a "username" (what is set as the DN of the cert for k8s to use later) from stdin
Generates a Private Key and CSR (in PEM)
-> Adds the CSR PEM to a kubernetes Object and deploys it to the cluster.
-> Appends the approval to the status (same thing `kubectl certificate approve` is doing)
-> Waits and pulls the signed user cert
-> uses everything to build a kubeconfig and write it to `$HOME/.kube/` 
```

This is not critical to the infrastructure or system in any way. So at worse this process can be done manually too.

### Gateway-API
I opted to include gateway-api in this deployment for a practical reason. While Ingresses may be familiar (and I did make sure include that functionality in the core demo). Gateway-api is the future. So it's not a question of "if" moreso "when". Currently, we can deploy ingress and gateway-api side-by-side so it's beneficial to adopt it when possible.

Gateway-API has many benefits such as cleaner and more defined seperations of concerns between developers and operators making for a much more robust security model.

### Traefik
With the deprication of `ingress-nginx` it's important to choose a stable and ingress/gateway solution. Personally I have worked with Traefik quite a bit when building k3s so it was the familiar option.



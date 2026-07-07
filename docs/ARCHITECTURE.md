# Architecture Design Choices and Decisions.

In this document I hope to show the current architecture as it's laid out by this repo. I will go over some of the choices I made and why for each part.

## Why so many automation tools?
This is a question that seemingly comes up quite a bit. The short answer is seperations of concerns. But let's take a look at our stack and talk through what it is all doing and why it's isolationed like it its.

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
-> Open east <-> west traffic between nodes. while I could have restricted this to known ports between the nodes there are better and more kubernetes native patterns for this such as Ciliums "Host Network Policies" whihc are much more portable for hybrid installs.
-> tighter access to Kube-API. Kubernetes secures it's API with mTLS which is pretty strong and depending on the algorithm used is going to be like breaking https. That said for long running infrastructure there is stilla risk of exploits on publically exposed administration services. So depending on the lifecycle of this environment it would be wise to maybe use a Jumphost or even Teleport to avoid accessing it outside of internal endpoints.
```

With Security being a tradeoff between complexity cost and Defense I feel I provided the most practical defaults for the request.

### Ansible - Machine configuration
With the core infrastructure set up we will have access to some bare bones linux nodes. We need to provision them with kubeadm to create a kubernetes cluster. This Ansible code sets up the machines as per install requirements of the [official kubernetes installation guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/).

***Note: It's worth mentioning that technically nodes can be run with*** [swap activated](https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/).

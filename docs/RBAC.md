# Cluster RBAC
Manual deployments into clusters requires a set of delicate permissions to assure the user can accomplish their core task while similtaniously not having over-reaching permissions that introduce the risk of cluster exploitation. Hence when giving users access and creating roles we want to assure we are following the pattern of principal of least priveleged (PoLP).

This means we need to be clear, explicit and intentional about
```
-> What tasks need to be accomplished.
-> What permissions to resources are required to accomplish them
-> What are the tradeoffs for granting access.
```

Below I want to go over every single permission I gave to the nginx-deployer user and why I gave them. This should hopefully reflect and be used to document the design.

## Role versus ClusterRole
I want to make special note as to why I'm using a "role/rolebinding" as opposed to clusterrole/clusterrolebinding.

The main difference between "roles" and "clusterroles" is "roles" are namespaced meaning they only apply the policy to the single namespace they are tied to. ClusterRoles on the other hand grant resources permissively across namespaces. Our developer user needs to only be concerned with their own namespace for their app and nothing else. So for this reason we are only granting them access to the namespace that they are appart of.

## NGINX App developer permissions

Let's start with the resources that are given full read and write access within the cluster.

### ingress resources
The user will need to create both traditional ingress objects as well as Gateway-api "gateway" configurations as well as httproutes for their webapp for this reason the user needs to be able to directly create, read, modify and update these resources. They are a part of the applications core pattern and something a developer would likely need access to. These resources are:

```
ingresses.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
```

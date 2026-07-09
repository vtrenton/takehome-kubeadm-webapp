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

### Ingress resources
The user will need to create both traditional ingress objects as well as Gateway-api "gateway" configurations as well as httproutes for their webapp for this reason the user needs to be able to directly create, read, modify and update these resources. They are a part of the applications core pattern and something a developer would likely need access to. These resources are:

```
ingresses.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
```
### Services
Consiquently of creating their own networking. Publishing static service endpoints is pretty important. For this reason the Developer is granted full access to the Services.

### Certificate Management Resources
The user will need to be able set up an Issuer and Certificate Object which will create and maintain the TLS secret. In this case the issuer we're configuring is generating self-signed Certificates. In a production deployment we would use signed Certificates from a Trusted CA.

The list of these resources which will have full read and write access are:
```
issuers.cert-manager.io
certificates.cert-manager.io
```
It's worth noting that some times the issuer is deployed and maintained by the administrator so the devs can consume them. This is not really needed for the current approch but a valid callout none-the-less

### Secrets
The Secrets resource is special and we can see we have full access to it. But the reason is intentional. Helm stores release state information in secrets. Now this can be bypassed by setting `HELM_DRIVER=configmap` to use a configmap instead.
But this creates additional user toil and an extra avenue for errors. Meanwhile, we have to thing that someone who has access to Deployments in a namespace already has access to secrets. The user could simply mount the secret and export it as an ENV VAR.
Because of this the developer is granted access to the secrets **only in the application namespace**

### Deployments
The Developer will be creating deployment specs for their application that will be managed by the deployment controller. The deployment controller will build the proper replicasets and pods from this spec and deploy them for the user.

### Replicasets
The replicasets will be managed by the controller directly. Developers can view them for troubleshooting purposes but should not be directly creating or deleting them.

### Pods
Pods are managed by replicasets which are managed by the deployemnts. Much like the replicaset itself. There is little reason a user needs to create a pod outside of a deployment. For this reason, users can see the running pods but CANNOT create or delete them. That will need to be handled by an Admin.

***Pods/Logs:***
It's worth noteing that there is a subresource of pod that we want called Logs. This will allow our devs to see the stdout and stderr of their application in a read only manner to troubleshoot their deployments.

## Default Deny
Lastly, it's important to note that users will not have access to the resources not explicitaly granted these permissions and because this is a role ONLY the namespace that this role is in. We can verify a lot of these permissions with `kubectl auth can-i`
```bash
$ kubectl --kubeconfig $HOME/.kube/nginx-deployer-kubeconfig.yaml \
-n nginx-manual \
auth can-i get pods --subresource=log
yes
$ kubectl --kubeconfig $HOME/.kube/nginx-deployer-kubeconfig.yaml \
-n nginx-manual \
auth can-i get pods --subresource=exec
no
$ kubectl --kubeconfig $HOME/.kube/nginx-deployer-kubeconfig.yaml \
-n nginx-manual \
auth can-i create pod
no
$ kubectl --kubeconfig $HOME/.kube/nginx-deployer-kubeconfig.yaml \
-n nginx-manual \
auth can-i create deployment
yes

```

# Webapp Takehome Project

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

## Getting up and running
Check out the [Running Docs](RUNNING.md) to see how to get the enviroment up and running step-by-step.

Otherwise, If you want to do it the hands off way:
I created a script of every step in the RUNNING docs called [go.sh](go.sh)

**Note: please run this from the project directory root!**

```bash
./go.sh
```

## Infrastructure Details
For a more detailed layout of the Infrastructure, justifcations and thought process check out the [Infrastructure docs](docs/INFRASTRUCTURE.md)

## Tearing down
Thankfully clean up is actually very easy.
```
terraform --chdir=terraform destroy
rm ~/.kube/nginx-deployer-kubeconfig.yaml
rm -r out/
```
You don't need to do any of the file cleanup for additional redeployments - just terraform destroy.

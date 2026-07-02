# kubeadm Gateway take-home

This repository starts with Terraform infrastructure for a kubeadm-based Kubernetes cluster on EC2.

## Terraform scope

Terraform owns:

- VPC, public subnets, route table, internet gateway
- EC2 key pair
- one control-plane EC2 instance
- two worker EC2 instances by default
- node security group
- public AWS Network Load Balancer
- TCP 80/443 listeners
- target group attachments to worker instances only
- generated Ansible inventory output

Terraform intentionally does **not** install Kubernetes. Ansible will consume the generated inventory and run the kubeadm bootstrap flow.

## First run

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform fmt -recursive
terraform validate
terraform apply

terraform output -raw ansible_inventory > ../ansible/inventory.ini
```

## Design notes

The public NLB forwards TCP 80/443 directly to the worker EC2 instances. Traefik will later run on worker nodes and bind 80/443, allowing TLS termination inside Kubernetes via Gateway API and cert-manager.

The control-plane node is not registered in the NLB target groups.

variable "project_name" {
  description = "Name prefix used for AWS resources."
  type        = string
  default     = "kubeadm-gateway"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "availability_zones" {
  description = "Optional explicit availability zones. If null, Terraform uses the first N available AZs in the selected region."
  type        = list(string)
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR range for the lab VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs. Use at least two for the NLB and worker placement."
  type        = list(string)
  default     = ["10.50.1.0/24", "10.50.2.0/24"]
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key Terraform should register as an EC2 key pair. Use an absolute path; Terraform does not reliably expand '~'."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to nodes and access the Kubernetes API. Use your current public IP as /32."
  type        = string
}

variable "allowed_web_cidr_blocks" {
  description = "CIDRs allowed to reach worker nodes on ports 80/443. For a public demo, leave as 0.0.0.0/0."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_user" {
  description = "Default SSH user for the chosen AMI."
  type        = string
  default     = "ubuntu"
}

variable "instance_type" {
  description = "EC2 instance type for all Kubernetes nodes."
  type        = string
  default     = "t3.medium"
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size for each node."
  type        = number
  default     = 30
}

variable "ubuntu_ami_ssm_parameter" {
  description = "SSM public parameter for the latest Ubuntu 24.04 LTS amd64 EBS gp3 AMI."
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

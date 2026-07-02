resource "aws_security_group" "node_common" {
  name        = "${var.project_name}-node-common"
  description = "Common access and private node-to-node traffic for kubeadm nodes"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-node-common"
  }
}

resource "aws_security_group" "control_plane_api" {
  name        = "${var.project_name}-control-plane-api"
  description = "Public Kubernetes API access for the control-plane node"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-control-plane-api"
  }
}

resource "aws_security_group" "worker_edge" {
  name        = "${var.project_name}-worker-edge"
  description = "Public HTTP/HTTPS access for Traefik running on worker nodes"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-worker-edge"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_operator" {
  security_group_id = aws_security_group.node_common.id
  description       = "SSH from allowed CIDR"
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "node_to_node_all" {
  security_group_id            = aws_security_group.node_common.id
  description                  = "All node-to-node traffic inside the cluster security group"
  referenced_security_group_id = aws_security_group.node_common.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "kube_api_from_operator" {
  security_group_id = aws_security_group.control_plane_api.id
  description       = "Kubernetes API from allowed CIDR"
  cidr_ipv4         = var.allowed_kube_api_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "worker_http" {
  for_each = toset(var.allowed_web_cidr_blocks)

  security_group_id = aws_security_group.worker_edge.id
  description       = "HTTP to worker-hosted Traefik"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "worker_https" {
  for_each = toset(var.allowed_web_cidr_blocks)

  security_group_id = aws_security_group.worker_edge.id
  description       = "HTTPS to worker-hosted Traefik"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "node_common_all_ipv4" {
  security_group_id = aws_security_group.node_common.id
  description       = "Allow all outbound IPv4"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

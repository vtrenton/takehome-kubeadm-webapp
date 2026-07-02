resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-nodes"
  description = "Security group for kubeadm nodes"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-nodes"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_operator" {
  security_group_id = aws_security_group.nodes.id
  description       = "SSH from operator"
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "kube_api_from_operator" {
  security_group_id = aws_security_group.nodes.id
  description       = "Kubernetes API from operator"
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "node_to_node_all" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "All node-to-node traffic inside the cluster security group"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "web_http" {
  for_each = toset(var.allowed_web_cidr_blocks)

  security_group_id = aws_security_group.nodes.id
  description       = "HTTP to worker-hosted Traefik"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "web_https" {
  for_each = toset(var.allowed_web_cidr_blocks)

  security_group_id = aws_security_group.nodes.id
  description       = "HTTPS to worker-hosted Traefik"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.nodes.id
  description       = "Allow all outbound IPv4"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

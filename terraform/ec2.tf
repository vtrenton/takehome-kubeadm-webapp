resource "aws_key_pair" "operator" {
  key_name   = "${var.project_name}-operator"
  public_key = file(local.ssh_public_key_path)

  tags = {
    Name = "${var.project_name}-operator"
  }
}

resource "aws_instance" "control_plane" {
  ami           = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public["0"].id
  vpc_security_group_ids = [
    aws_security_group.node_common.id,
    aws_security_group.control_plane_api.id,
  ]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.operator.key_name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${var.project_name}-cp-1"
    Role = "control-plane"
  }
}

resource "aws_instance" "workers" {
  for_each = local.worker_nodes

  ami           = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[each.value.subnet_key].id
  vpc_security_group_ids = [
    aws_security_group.node_common.id,
    aws_security_group.worker_edge.id,
  ]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.operator.key_name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${var.project_name}-${each.key}"
    Role = "worker"
  }
}

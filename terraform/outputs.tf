output "control_plane_public_ip" {
  description = "Public IP for SSH to the control-plane node."
  value       = aws_instance.control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP used for kubeadm apiserver advertise address."
  value       = aws_instance.control_plane.private_ip
}

output "worker_public_ips" {
  description = "Worker public IPs by logical name."
  value       = { for name, instance in aws_instance.workers : name => instance.public_ip }
}

output "worker_private_ips" {
  description = "Worker private IPs by logical name."
  value       = { for name, instance in aws_instance.workers : name => instance.private_ip }
}

output "nlb_dns_name" {
  description = "Public DNS name of the AWS Network Load Balancer."
  value       = aws_lb.edge.dns_name
}

output "ansible_inventory" {
  description = "Generated Ansible inventory for the kubeadm bootstrap playbook."
  value = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    node_user                = var.node_user
    control_plane_public_ip  = aws_instance.control_plane.public_ip
    control_plane_private_ip = aws_instance.control_plane.private_ip
    workers = [
      for name, instance in aws_instance.workers : {
        name       = name
        public_ip  = instance.public_ip
        private_ip = instance.private_ip
      }
    ]
  })
}

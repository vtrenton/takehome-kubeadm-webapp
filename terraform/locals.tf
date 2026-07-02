data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = var.ubuntu_ami_ssm_parameter
}

locals {
  selected_azs = var.availability_zones != null ? var.availability_zones : slice(
    data.aws_availability_zones.available.names,
    0,
    length(var.public_subnet_cidrs)
  )

  public_subnets = {
    for idx, cidr in var.public_subnet_cidrs :
    tostring(idx) => {
      cidr = cidr
      az   = local.selected_azs[idx]
    }
  }

  worker_nodes = {
    for idx in range(var.worker_count) :
    format("worker-%02d", idx + 1) => {
      index      = idx
      subnet_key = tostring(idx % length(var.public_subnet_cidrs))
    }
  }

  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

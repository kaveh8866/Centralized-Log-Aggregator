# Wires the network and compute modules together.
#
# PORTABILITY (AWS / GCP):
#   OCI VCN + IGW + route table + security list + subnet
#     ≈ AWS  VPC + internet gateway + route table + security group + subnet
#     ≈ GCP  VPC network + default internet route + firewall rule + subnetwork
#   OCI oci_core_instance (VM.Standard.A1.Flex)
#     ≈ AWS  aws_instance (t3.micro / t4g.small free tier)
#     ≈ GCP  google_compute_instance (e2-micro free tier)
# Only this file and the two modules are cloud-specific; docker/, configs/ and
# the collector image never change between providers.

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(var.freeform_tags, {
    environment = var.environment
    managed_by  = "opentofu"
    stage       = "2-iac"
  })

  # Cloud-init renders the same bootstrap on every cloud: it only installs
  # Docker and opens the two application ports, nothing credential-bearing.
  user_data = base64encode(
    templatefile("${path.module}/cloud-init.yaml.tftpl", {
      project_name = var.project_name
      grafana_port = var.grafana_port
      loki_port    = var.loki_port
    })
  )
}

module "network" {
  source = "./modules/network"

  compartment_id       = var.compartment_ocid
  name_prefix          = local.name_prefix
  vcn_cidr             = var.vcn_cidr
  subnet_cidr          = var.subnet_cidr
  ssh_allowed_cidr     = var.ssh_allowed_cidr
  grafana_allowed_cidr = var.grafana_allowed_cidr
  loki_allowed_cidr    = var.loki_allowed_cidr
  enable_loki_ingress  = var.enable_loki_ingress
  grafana_port         = var.grafana_port
  loki_port            = var.loki_port
  vcn_dns_label        = "cloudguard"
  subnet_dns_label     = "public"
  freeform_tags        = local.tags
}

module "compute" {
  source = "./modules/compute"

  compartment_id         = var.compartment_ocid
  tenancy_ocid           = var.tenancy_ocid
  name_prefix            = local.name_prefix
  subnet_id              = module.network.subnet_id
  availability_domain    = var.availability_domain
  instance_shape         = var.instance_shape
  instance_ocpus         = var.instance_ocpus
  instance_memory_gbs    = var.instance_memory_gbs
  boot_volume_size_gbs   = var.boot_volume_size_gbs
  ssh_public_key         = var.ssh_public_key
  user_data              = local.user_data
  hostname_label         = var.hostname_label
  image_id               = var.image_id
  image_operating_system = var.image_operating_system
  image_os_version       = var.image_operating_system_version
  freeform_tags          = local.tags
}

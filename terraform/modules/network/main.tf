# OCI network module — public VCN with a single public subnet.
#
# PORTABILITY — the same five resources on the other free tiers:
#
#   | OCI (here)                  | AWS                              | GCP                                   |
#   | --------------------------- | -------------------------------- | ------------------------------------- |
#   | oci_core_vcn                | aws_vpc                          | google_compute_network                |
#   | oci_core_internet_gateway   | aws_internet_gateway             | (implicit for a default-route VPC)    |
#   | oci_core_route_table        | aws_route_table + aws_route      | google_compute_route                  |
#   | oci_core_security_list      | aws_security_group + rules       | google_compute_firewall               |
#   | oci_core_subnet             | aws_subnet                       | google_compute_subnetwork             |
#
# The ingress contract (22, grafana_port, loki_port) is identical on all three,
# so a port of this module only swaps resource types — the variables and the
# exposed IDs stay the same.

locals {
  # Loki has no authentication in this stage, so its ingress rule must never be
  # world-open. If a tfvars still carries 0.0.0.0/0, fall back to the private
  # subnet CIDR: only hosts inside the VCN can then reach the API.
  loki_source_cidr = var.loki_allowed_cidr == "0.0.0.0/0" ? var.subnet_cidr : var.loki_allowed_cidr

  # One rule list drives the security list, so a new port is added in exactly
  # one place and stays readable in the plan output.
  ingress_rules = concat(
    [
      {
        description = "SSH administration"
        port        = 22
        cidr        = var.ssh_allowed_cidr
      },
      {
        description = "Grafana UI"
        port        = var.grafana_port
        cidr        = var.grafana_allowed_cidr
      },
    ],
    var.enable_loki_ingress ? [
      {
        description = "Loki HTTP API (push + query) — private only"
        port        = var.loki_port
        cidr        = local.loki_source_cidr
      },
    ] : [],
  )
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_block     = var.vcn_cidr
  display_name   = "${var.name_prefix}-vcn"
  dns_label      = var.vcn_dns_label
  freeform_tags  = var.freeform_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

# Dedicated route table instead of mutating the VCN's default one: the VCN stays
# reusable and the routing intent is explicit in the plan.
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-public-rt"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
    description       = "Default IPv4 egress to the internet gateway"
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-public-sl"
  freeform_tags  = var.freeform_tags

  dynamic "ingress_security_rules" {
    for_each = local.ingress_rules

    content {
      protocol    = "6" # TCP
      source      = ingress_security_rules.value.cidr
      source_type = "CIDR_BLOCK"
      description = ingress_security_rules.value.description

      tcp_options {
        min = ingress_security_rules.value.port
        max = ingress_security_rules.value.port
      }
    }
  }

  # "protocol 6, destination port 1234" would block apt/docker/ghcr pulls, so
  # egress stays open. Tighten to 443 + the Loki endpoint for a hardened build.
  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    description      = "Allow all egress (OS updates, image pulls, log shipping)"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.subnet_cidr
  display_name               = "${var.name_prefix}-public-subnet"
  dns_label                  = var.subnet_dns_label
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = var.freeform_tags
}

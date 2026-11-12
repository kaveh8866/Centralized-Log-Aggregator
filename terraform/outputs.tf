# Connection details for the provisioned host.
#
# These outputs are the hand-off to Stage 1's compose stack: the public IP plus
# the three endpoints the container stack already publishes.

output "instance_public_ip" {
  description = "Public IPv4 address of the log aggregator host."
  value       = module.compute.public_ip
}

output "instance_private_ip" {
  description = "Private IPv4 address inside the VCN."
  value       = module.compute.private_ip
}

output "instance_id" {
  description = "OCID of the compute instance."
  value       = module.compute.instance_id
}

output "instance_shape" {
  description = "Shape actually requested, with its OCPU and memory envelope."
  value = {
    shape  = var.instance_shape
    ocpus  = var.instance_ocpus
    memory = var.instance_memory_gbs
    flex   = module.compute.is_flex_shape
  }
}

output "availability_domain" {
  description = "Availability domain the instance landed in."
  value       = module.compute.availability_domain
}

output "image_id" {
  description = "Image resolved (or supplied) for the instance."
  value       = module.compute.image_id
}

output "vcn_id" {
  description = "OCID of the created VCN."
  value       = module.network.vcn_id
}

output "subnet_id" {
  description = "OCID of the public subnet."
  value       = module.network.subnet_id
}

output "security_list_id" {
  description = "OCID of the security list holding the ingress rules."
  value       = module.network.security_list_id
}

output "connection_endpoints" {
  description = "Ready-to-use endpoints and commands for the aggregator."
  value = {
    ssh     = "ssh ubuntu@${module.compute.public_ip}"
    grafana = "http://${module.compute.public_ip}:${var.grafana_port}"
    # Loki has no authentication: it binds to loopback on the host and the
    # security list carries no rule for it. Reach it through an SSH tunnel.
    loki_tunnel = "ssh -L ${var.loki_port}:localhost:${var.loki_port} ubuntu@${module.compute.public_ip}  # then http://localhost:${var.loki_port}"
  }
}

output "deploy_next_step" {
  description = "Reminder of how the stack itself is deployed — IaC provisions the host, compose runs the pipeline."
  value       = "ssh ubuntu@${module.compute.public_ip} 'git clone <repo-url> && cd Centralized-Log-Aggregator && cp .env.example .env && docker compose -f docker/docker-compose.yml up -d --build'"
}

output "instance_id" {
  description = "OCID of the compute instance."
  value       = oci_core_instance.this.id
}

output "public_ip" {
  description = "Public IPv4 address of the primary VNIC."
  value       = data.oci_core_vnic.primary.public_ip_address
}

output "private_ip" {
  description = "Private IPv4 address inside the VCN."
  value       = data.oci_core_vnic.primary.private_ip_address
}

output "availability_domain" {
  description = "Availability domain the instance was created in."
  value       = oci_core_instance.this.availability_domain
}

output "is_flex_shape" {
  description = "Whether the shape uses shape_config (flex) semantics."
  value       = local.is_flex_shape
}

output "image_id" {
  description = "Image OCID actually used."
  value       = local.resolved_image_id
}

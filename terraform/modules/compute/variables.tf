variable "compartment_id" {
  description = "Compartment that owns the instance."
  type        = string
}

variable "tenancy_ocid" {
  description = "Tenancy OCID, used to list availability domains."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource display names."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the primary VNIC attaches to."
  type        = string
}

variable "availability_domain" {
  description = "Explicit availability domain, or null for the first one in the region."
  type        = string
  default     = null
}

variable "instance_shape" {
  description = "Compute shape, e.g. VM.Standard.A1.Flex."
  type        = string
}

variable "instance_ocpus" {
  description = "OCPUs for flex shapes."
  type        = number
}

variable "instance_memory_gbs" {
  description = "Memory in GB for flex shapes."
  type        = number
}

variable "boot_volume_size_gbs" {
  description = "Boot volume size in GB."
  type        = number
}

variable "ssh_public_key" {
  description = "OpenSSH public key injected via instance metadata."
  type        = string
}

variable "user_data" {
  description = "Base64-encoded cloud-init payload."
  type        = string
}

variable "hostname_label" {
  description = "Hostname label for the primary VNIC."
  type        = string
}

variable "image_id" {
  description = "Explicit image OCID, or null to resolve one by OS/version/shape."
  type        = string
  default     = null
}

variable "image_operating_system" {
  description = "OS family used when image_id is null."
  type        = string
  default     = "Canonical Ubuntu"
}

variable "image_os_version" {
  description = "OS version used when image_id is null."
  type        = string
  default     = "24.04"
}

variable "freeform_tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

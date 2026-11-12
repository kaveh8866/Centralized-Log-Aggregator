variable "compartment_id" {
  description = "Compartment that owns the VCN resources."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every resource display name."
  type        = string
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
}

variable "vcn_dns_label" {
  description = "DNS label for the VCN (letters/digits, max 15 characters)."
  type        = string
}

variable "subnet_dns_label" {
  description = "DNS label for the subnet (letters/digits, max 15 characters)."
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "Source CIDR allowed to reach TCP 22."
  type        = string
}

variable "grafana_port" {
  description = "Grafana port allowed inbound."
  type        = number
}

variable "grafana_allowed_cidr" {
  description = "Source CIDR allowed to reach the Grafana port."
  type        = string
}

variable "loki_port" {
  description = "Loki HTTP port allowed inbound."
  type        = number
}

variable "loki_allowed_cidr" {
  description = "Source CIDR allowed to reach the Loki port."
  type        = string
}

variable "enable_loki_ingress" {
  description = "Creates the Loki ingress rule when true."
  type        = bool
}

variable "freeform_tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

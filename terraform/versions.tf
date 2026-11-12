# Centralized Log Aggregator — OCI environment (Stage 2)
#
# Terraform/OpenTofu root module. Creates the network and the compute instance
# that runs the Stage 1 compose stack. Everything cloud-specific is confined to
# this directory and modules/compute; the log pipeline itself is unchanged.
#
# PORTABILITY (AWS / GCP): see modules/network/main.tf and modules/compute/main.tf
# for the 1:1 mapping of each resource, and README.md § "Porting to AWS or GCP".

terraform {
  # OpenTofu 1.6+ and Terraform 1.6+ both satisfy this configuration.
  required_version = ">= 1.6.0"

  required_providers {
    oci = {
      source = "oracle/oci"
      # 6.x is the current major line; allow newer majors only after testing.
      version = ">= 6.20.0, < 8.0.0"
    }
  }

  # State is local for Stage 2: one operator, one environment.
  # Move to an encrypted remote backend before any shared use — the repository
  # must never contain state, because state holds resource identifiers and
  # provisioned secrets. Example (S3-compatible, works for OCI/AWS):
  #
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "centralized-log-aggregator/oci.tfstate"
  #   region = "eu-frankfurt-1"
  # }
}

provider "oci" {
  region = var.region

  # API-key authentication. Every value comes from variables (or from
  # ~/.oci/config when left null) — never from a file in this repository.
  #
  # For Cloud Shell / session-token auth instead of an API key, set
  # `auth = "SecurityToken"` and point `config_file_profile` at the profile
  # OCI generated.
  tenancy_ocid        = var.tenancy_ocid
  user_ocid           = var.user_ocid
  fingerprint         = var.fingerprint
  private_key_path    = var.private_key_path
  config_file_profile = var.config_file_profile
}

# Child modules must declare the provider *source* they consume. Without this,
# Terraform/OpenTofu assumes hashicorp/oci, whose resource schema differs — the
# root module's constraint alone does not bind module resources to oracle/oci.
#
# The version constraint lives in the root versions.tf; a module must not pin it,
# so callers stay free to pick the provider version.
terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

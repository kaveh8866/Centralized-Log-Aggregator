# Declares oracle/oci explicitly: a module without this block resolves its
# resources against hashicorp/oci, where oci_core_vnic exposes different
# attributes and init downloads the wrong provider entirely.
#
# Version constraints are the root module's responsibility.
terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

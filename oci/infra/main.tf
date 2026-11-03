# Provider resources directly: there is no endorsed upstream module for OCI (CONVENTIONS.md section 2).
# Docs: infrastructure-recommendations "Networking" and "Node pools"; oci.md "OKE cluster".

# Credentials come from the environment or ~/.oci/config (OCI_CLI_* / TF_VAR_*), never from code.
provider "oci" {
  region = var.region
}

# Globally unique names (buckets, dynamic group, policies, registry repository) carry this suffix so two copies
# can run side by side in one tenancy.
resource "random_id" "suffix" {
  byte_length = 3
}

data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid
}

# "all" rather than the cluster OCID: the image list is filtered to the cluster version in locals, and a read that
# does not depend on the cluster resolves at plan time instead of being deferred to apply.
data "oci_containerengine_node_pool_option" "this" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_ocid
}

locals {
  labels      = merge({ "managed-by" = "terraform", "stack" = var.name }, var.labels)
  unique_name = "${var.name}-${random_id.suffix.hex}"

  # Null only gets past validation with allow_public_api_endpoint = true, which asks for an open endpoint.
  api_allowed_cidr = coalesce(var.api_allowed_cidr, "0.0.0.0/0")

  availability_domains = [for ad in data.oci_identity_availability_domains.this.availability_domains : ad.name]

  # OKE node images are named "...-OKE-<k8s version>-<build>"; pick the x86 non-GPU image matching the cluster
  # version. Fails at plan time if OKE publishes none for the version.
  node_image_id = [
    for s in data.oci_containerengine_node_pool_option.this.sources : s.image_id
    if strcontains(s.source_name, "-OKE-${trimprefix(var.kubernetes_version, "v")}-")
    && !strcontains(s.source_name, "aarch64") && !strcontains(s.source_name, "GPU")
  ][0]
}

# --- Network: a large private subnet for nodes and pods, a small public subnet, NAT egress so nodes reach
# registries and *.unionai.cloud (TCP 443, 7844).

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  display_name   = var.name
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "union"
  freeform_tags  = local.labels
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-igw"
  freeform_tags  = local.labels
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-nat"
  freeform_tags  = local.labels
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-public"
  freeform_tags  = local.labels

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-private"
  freeform_tags  = local.labels

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }
}

# Intra-VCN traffic is open (node <-> API endpoint 6443/12250, pod <-> pod); only the Kubernetes API port is
# exposed beyond the VCN, and only to api_allowed_cidr (any address only with allow_public_api_endpoint = true).
resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-private"
  freeform_tags  = local.labels

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = var.vcn_cidr
    protocol = "all"
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-public"
  freeform_tags  = local.labels

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = var.vcn_cidr
    protocol = "all"
  }

  ingress_security_rules {
    source   = local.api_allowed_cidr
    protocol = "6" # TCP
    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${var.name}-private"
  cidr_block                 = var.private_subnet_cidr
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  freeform_tags              = local.labels
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.this.id
  display_name      = "${var.name}-public"
  cidr_block        = var.public_subnet_cidr
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]
  freeform_tags     = local.labels
}

# --- Cluster

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_ocid
  name               = var.name
  kubernetes_version = var.kubernetes_version
  vcn_id             = oci_core_vcn.this.id
  freeform_tags      = local.labels

  # VCN-native pod networking: pod IPs come from the private subnet, matching the docs' "size the private
  # subnet for peak concurrent pods" guidance.
  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }

  endpoint_config {
    subnet_id            = oci_core_subnet.public.id
    is_public_ip_enabled = true
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.public.id]
  }
}

# The cluster resource does not expose its CA; the kubeconfig OKE generates does (the cluster_ca_certificate output,
# read by the helm root). With token version 2.0.0 that kubeconfig holds no credential, only the
# `oci ce cluster generate-token` exec entry.
data "oci_containerengine_cluster_kube_config" "this" {
  cluster_id    = oci_containerengine_cluster.this.id
  endpoint      = "PUBLIC_ENDPOINT"
  token_version = "2.0.0"
}

resource "oci_containerengine_node_pool" "system" {
  compartment_id     = var.compartment_ocid
  cluster_id         = oci_containerengine_cluster.this.id
  name               = "${var.name}-system"
  kubernetes_version = var.kubernetes_version
  node_shape         = var.system_node_pool.shape
  freeform_tags      = local.labels

  node_shape_config {
    ocpus         = var.system_node_pool.ocpus
    memory_in_gbs = var.system_node_pool.memory_gbs
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = local.node_image_id
  }

  node_config_details {
    size          = var.system_node_pool.size
    freeform_tags = local.labels

    # One placement per availability domain so the pool spreads over all of them.
    dynamic "placement_configs" {
      for_each = local.availability_domains
      content {
        availability_domain = placement_configs.value
        subnet_id           = oci_core_subnet.private.id
      }
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [oci_core_subnet.private.id]
      max_pods_per_node = 31
    }
  }
}

resource "oci_containerengine_node_pool" "worker" {
  # The worker pool is optional: without it task pods run on the system pool.
  count = var.worker_node_pool.enabled ? 1 : 0

  compartment_id     = var.compartment_ocid
  cluster_id         = oci_containerengine_cluster.this.id
  name               = "${var.name}-worker"
  kubernetes_version = var.kubernetes_version
  node_shape         = var.worker_node_pool.shape
  freeform_tags      = local.labels

  node_shape_config {
    ocpus         = var.worker_node_pool.ocpus
    memory_in_gbs = var.worker_node_pool.memory_gbs
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = local.node_image_id
  }

  node_config_details {
    size          = var.worker_node_pool.size
    freeform_tags = local.labels

    # One placement per availability domain so the pool spreads over all of them.
    dynamic "placement_configs" {
      for_each = local.availability_domains
      content {
        availability_domain = placement_configs.value
        subnet_id           = oci_core_subnet.private.id

        # Preemptible capacity is a per-placement setting, only set when the pool asks for it.
        dynamic "preemptible_node_config" {
          for_each = var.worker_node_pool.preemptible ? [1] : []
          content {
            preemption_action {
              type                    = "TERMINATE"
              is_preserve_boot_volume = false
            }
          }
        }
      }
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [oci_core_subnet.private.id]
      max_pods_per_node = 31
    }
  }
}

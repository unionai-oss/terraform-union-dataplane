mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = { names = ["zone-a", "zone-b", "zone-c", "zone-d"] }
  }
}
mock_provider "google-beta" {}
mock_provider "random" {}

# hex is computed, so it is unknown during plan unless overridden there.
override_resource {
  target          = random_id.suffix
  override_during = plan
  values          = { hex = "abcd1234" }
}

# The module's endpoint_dns output indexes a block that mock providers leave empty.
override_module {
  target = module.gke
  outputs = {
    ca_certificate     = "Y2E="
    endpoint           = "192.0.2.1"
    identity_namespace = "test-project.svc.id.goog"
    name               = "union-dataplane"
    service_account    = "node@test-project.iam.gserviceaccount.com"
  }
}

# email and name are computed, so they are unknown during plan unless overridden there.
override_resource {
  target          = google_service_account.union
  override_during = plan
  values = {
    email = "union-dataplane-system@test-project.iam.gserviceaccount.com"
    name  = "projects/test-project/serviceAccounts/union-dataplane-system@test-project.iam.gserviceaccount.com"
  }
}

# The repository's full name is computed; the IAM members take it as their target.
override_resource {
  target          = google_artifact_registry_repository.this
  override_during = plan
  values          = { name = "projects/test-project/locations/test-region1/repositories/union-dataplane" }
}

variables {
  project_id                 = "test-project"
  region                     = "test-region1"
  master_authorized_networks = [{ cidr_block = "203.0.113.0/24", display_name = "office" }]
}

run "defaults" {
  command = plan

  assert {
    condition     = google_storage_bucket.metadata.name == "union-dataplane-metadata-abcd1234"
    error_message = "metadata bucket name must be <name>-metadata-<suffix>"
  }
  assert {
    condition     = google_storage_bucket.fast_registration.name == "union-dataplane-fast-reg-abcd1234"
    error_message = "fast-registration bucket name must be <name>-fast-reg-<suffix>"
  }
  assert {
    condition     = google_artifact_registry_repository.this.repository_id == "union-dataplane"
    error_message = "registry repository must be named after var.name"
  }
  assert {
    condition     = google_service_account.union.account_id == "union-dataplane-system"
    error_message = "service account id must be <name>-system"
  }
  assert {
    condition     = google_storage_bucket.metadata.labels["managed-by"] == "terraform" && google_storage_bucket.metadata.labels["stack"] == "union-dataplane"
    error_message = "default labels must be applied"
  }
  assert {
    condition     = alltrue([for r in [google_storage_bucket.fast_registration, google_storage_bucket.metadata, google_artifact_registry_repository.this] : r.labels["managed-by"] == "terraform" && r.labels["stack"] == "union-dataplane"])
    error_message = "both buckets and the registry carry the labels"
  }
  assert {
    condition     = length(local.zones) == 3
    error_message = "cluster must use three zones by default so the system pool has three nodes"
  }

  assert {
    condition     = one(one(google_storage_bucket.fast_registration.lifecycle_rule).condition).age == 7
    error_message = "fast-registration objects must expire after 7 days by default"
  }

  assert {
    condition     = toset(one(google_storage_bucket.metadata.cors).method) == toset(["HEAD", "GET"]) && toset(one(google_storage_bucket.fast_registration.cors).method) == toset(["HEAD", "GET"])
    error_message = "both buckets need the Code Viewer CORS rule"
  }

  assert {
    condition     = toset(keys(google_service_account_iam_member.workload_identity)) == toset(["union-system", "union"])
    error_message = "union-system and union Kubernetes service accounts must be bound"
  }
  assert {
    condition     = google_service_account_iam_member.token_creator.role == "roles/iam.serviceAccountTokenCreator"
    error_message = "the service account needs token creator on itself for Image Builder"
  }
  assert {
    condition     = google_artifact_registry_repository_iam_member.node_reader.role == "roles/artifactregistry.reader"
    error_message = "node service account must be able to pull from the registry"
  }

  assert {
    condition     = local.cluster_security.enable_private_nodes && !local.cluster_security.enable_private_endpoint
    error_message = "nodes are private; the API endpoint is public but limited to authorized networks"
  }

  assert {
    condition     = local.cluster_security.identity_namespace == "enabled"
    error_message = "Workload Identity must be enabled on the cluster"
  }

  assert {
    condition     = local.cluster_security.master_authorized_networks == var.master_authorized_networks && length(local.cluster_security.master_authorized_networks) == 1
    error_message = "the authorized networks reach the cluster"
  }

  assert {
    condition     = local.nat.enable_dynamic_port_allocation && !local.nat.enable_endpoint_independent_mapping && local.nat.min_ports_per_vm == 32
    error_message = "Cloud NAT uses dynamic port allocation without endpoint-independent mapping"
  }

  # module.router is planned for real (only module.gke is overridden), so this reads the NAT resource it plans.
  assert {
    condition     = module.router.nat["union-dataplane-nat"].enable_dynamic_port_allocation && !module.router.nat["union-dataplane-nat"].enable_endpoint_independent_mapping && module.router.nat["union-dataplane-nat"].min_ports_per_vm == 32
    error_message = "the planned Cloud NAT uses dynamic port allocation without endpoint-independent mapping"
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity["union-system"].member == "serviceAccount:test-project.svc.id.goog[union/union-system]" && google_service_account_iam_member.workload_identity["union"].member == "serviceAccount:test-project.svc.id.goog[union/union]"
    error_message = "Workload Identity members are the union-system and union Kubernetes service accounts in the chart namespace"
  }

  assert {
    condition     = alltrue([for m in google_service_account_iam_member.workload_identity : m.role == "roles/iam.workloadIdentityUser" && m.service_account_id == google_service_account.union.name])
    error_message = "Workload Identity users are bound on the Union service account"
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.writer.member == "serviceAccount:union-dataplane-system@test-project.iam.gserviceaccount.com" && google_artifact_registry_repository_iam_member.writer.role == "roles/artifactregistry.writer" && google_artifact_registry_repository_iam_member.writer.repository == "projects/test-project/locations/test-region1/repositories/union-dataplane"
    error_message = "the Union service account, and only it, may write to the Artifact Registry repository"
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.node_reader.member == "serviceAccount:node@test-project.iam.gserviceaccount.com"
    error_message = "the node service account reads the repository"
  }

  assert {
    condition     = alltrue([for m in google_storage_bucket_iam_member.fast_registration : m.bucket == google_storage_bucket.fast_registration.name && m.member == "serviceAccount:${google_service_account.union.email}"]) && alltrue([for m in google_storage_bucket_iam_member.metadata : m.bucket == google_storage_bucket.metadata.name && m.member == "serviceAccount:${google_service_account.union.email}"])
    error_message = "each bucket grants only on itself, to the Union service account"
  }

  assert {
    condition     = toset(keys(google_storage_bucket_iam_member.fast_registration)) == toset(["roles/storage.objectAdmin", "roles/storage.legacyBucketReader", "roles/storage.bucketViewer"]) && toset(keys(google_storage_bucket_iam_member.metadata)) == toset(["roles/storage.objectAdmin", "roles/storage.legacyBucketReader", "roles/storage.bucketViewer"])
    error_message = "both buckets grant object admin plus the two bucket reader roles"
  }

  # module.gke is overridden above, so no assert can see what main.tf passes it, and the asserts on the cluster
  # security and pool locals would stay green if an argument stopped using them. Planning the real module instead does
  # not work: its endpoint_dns output indexes control_plane_endpoints_config, a block that is empty unless configured
  # and that mock providers cannot fill (override_resource and mock_resource only set computed attributes), and an
  # assert can read a child module's outputs but not its resources. So this assert reads the module "gke" block of
  # main.tf itself: each argument below must be exactly the local the other asserts check.
  assert {
    condition = alltrue([
      for argument, value in {
        enable_private_nodes       = "local.cluster_security.enable_private_nodes"
        enable_private_endpoint    = "local.cluster_security.enable_private_endpoint"
        master_authorized_networks = "local.cluster_security.master_authorized_networks"
        identity_namespace         = "local.cluster_security.identity_namespace"
        node_pools                 = "local.node_pools"
        cluster_resource_labels    = "local.labels"
        zones                      = "local.zones"
      } :
      length(regexall(
        "(?m)^ +${argument} += ${replace(value, ".", "\\.")}$",
        one(regexall("(?s)\nmodule \"gke\" \\{\n.*?\n\\}\n", file("${path.module}/main.tf"))),
      )) == 1
    ])
    error_message = "module.gke must take the cluster security settings, node pools, labels and zones from the locals the tests assert"
  }

  assert {
    condition     = [for p in local.node_pools : p.name] == ["system", "buildkit-pool"]
    error_message = "default pools are system and buildkit-pool"
  }
  assert {
    condition     = local.system_pool.autoscaling == false && local.system_pool.node_count == 1
    error_message = "system pool is fixed size, one node per zone"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.GOOGLE_PROJECT_ID == "test-project" && yamldecode(output.helm_values).global.GCP_REGION == "test-region1"
    error_message = "helm_values must carry project and region"
  }
  assert {
    condition     = yamldecode(output.helm_values).imageBuilder.registryName == "union-dataplane"
    error_message = "helm_values must name the registry repository"
  }
  assert {
    condition     = yamldecode(output.helm_values).global.BACKEND_IAM_ROLE_ARN == google_service_account.union.email && yamldecode(output.helm_values).global.WORKER_IAM_ROLE_ARN == google_service_account.union.email
    error_message = "helm_values must point the backend and worker roles at the Google service account"
  }
  assert {
    condition     = yamldecode(output.helm_values).global.METADATA_BUCKET == google_storage_bucket.metadata.name
    error_message = "METADATA_BUCKET is the metadata bucket"
  }
  assert {
    condition     = yamldecode(output.helm_values).global.FAST_REGISTRATION_BUCKET == google_storage_bucket.fast_registration.name
    error_message = "FAST_REGISTRATION_BUCKET is the fast-registration bucket"
  }
  assert {
    condition     = yamldecode(output.helm_values).global.GOOGLE_PROJECT_ID == var.project_id && yamldecode(output.helm_values).global.GCP_REGION == var.region
    error_message = "project and region keys follow the variables"
  }
  assert {
    condition     = yamldecode(output.helm_values).imageBuilder.registryName == google_artifact_registry_repository.this.repository_id
    error_message = "imageBuilder.registryName is the Artifact Registry repository"
  }
  assert {
    condition     = yamldecode(output.helm_values).global.CLUSTER_NAME == module.gke.name && yamldecode(output.helm_values).global.CLUSTER_NAME == "union-dataplane"
    error_message = "CLUSTER_NAME, which the chart requires, is the GKE cluster name"
  }
  assert {
    condition     = toset(keys(yamldecode(output.helm_values).global)) == toset(["CLUSTER_NAME", "GOOGLE_PROJECT_ID", "GCP_REGION", "METADATA_BUCKET", "FAST_REGISTRATION_BUCKET", "BACKEND_IAM_ROLE_ARN", "WORKER_IAM_ROLE_ARN"])
    error_message = "helm_values carries exactly these global keys: the org, control plane host and client ID are the helm root's"
  }
}

run "labels_merge_over_defaults" {
  command = plan

  variables {
    labels = { team = "data", stack = "override" }
  }

  assert {
    condition     = google_artifact_registry_repository.this.labels["team"] == "data" && google_artifact_registry_repository.this.labels["stack"] == "override"
    error_message = "var.labels must be merged over the defaults"
  }
}

run "api_endpoint_needs_authorized_networks" {
  command = plan

  variables {
    master_authorized_networks = []
  }

  expect_failures = [var.master_authorized_networks]
}

run "open_api_endpoint_needs_explicit_opt_in" {
  command = plan

  variables {
    master_authorized_networks = []
    allow_public_api_endpoint  = true
  }

  assert {
    condition     = length(local.cluster_security.master_authorized_networks) == 0
    error_message = "an empty list is accepted only with allow_public_api_endpoint = true"
  }
}

run "pools_optional_enabled" {
  command = plan

  variables {
    worker_node_pool   = { enabled = true }
    gpu_node_pool      = { enabled = true }
    buildkit_node_pool = { enabled = false }
  }

  assert {
    condition     = [for p in local.node_pools : p.name] == ["system", "worker", "gpu"]
    error_message = "worker and gpu pools must be added when enabled, buildkit removed"
  }
  assert {
    condition     = local.gpu_pool.min_count == 0 && local.worker_pool.min_count == 0
    error_message = "optional pools scale from zero"
  }
}

run "rejects_bad_name" {
  command = plan

  variables {
    name = "Not_Valid"
  }

  expect_failures = [var.name]
}

run "rejects_burstable_system_pool" {
  command = plan

  variables {
    system_node_pool = { machine_type = "e2-medium" }
  }

  expect_failures = [var.system_node_pool]
}

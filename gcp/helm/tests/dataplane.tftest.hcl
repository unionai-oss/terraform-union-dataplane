# The Union dataplane release (dataplane.tf), planned against the infra outputs of examples/gcp/infra/basic.tfvars
# (and, in one run, gpu.tfvars).

mock_provider "helm" {}
mock_provider "kubernetes" {}

# The infra root's outputs for the basic scenario (checks.sh keeps the keys equal to ../infra/outputs.tf, and
# ../infra/tests/contract.tftest.hcl the values).
override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
  }
}

variables {
  union_client_id          = "example-client-id"
  union_control_plane_host = "union.example.com"
  union_org_name           = "example-org"
}

run "defaults" {
  command = plan

  assert {
    condition     = helm_release.dataplane.chart == "dataplane" && helm_release.dataplane.repository == "https://unionai.github.io/helm-charts" && helm_release.dataplane.version == "2026.10.1"
    error_message = "the release installs the Union dataplane chart at the pinned version"
  }
  assert {
    condition     = helm_release.dataplane.name == "union" && helm_release.dataplane.namespace == "union" && helm_release.dataplane.create_namespace
    error_message = "the release is union, in the namespace infra bound Workload Identity for"
  }
  assert {
    condition     = output.namespace == "union" && output.chart_version == "2026.10.1"
    error_message = "the outputs name the release's namespace and chart version"
  }

  assert {
    condition     = helm_release.dataplane.values[0] == jsondecode(file("tests/fixtures/basic.json")).helm_values
    error_message = "the infra root's helm_values output reaches the release unchanged"
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).global.METADATA_BUCKET == "union-dataplane-metadata-abcd1234" && yamldecode(helm_release.dataplane.values[0]).global.FAST_REGISTRATION_BUCKET == "union-dataplane-fast-reg-abcd1234"
    error_message = "the buckets come from the infra state"
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).global.CLUSTER_NAME == "union-dataplane"
    error_message = "CLUSTER_NAME, which the chart requires, is the GKE cluster name from the infra state"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).provider == "gcp" && yamldecode(helm_release.dataplane.values[1]).storage == { provider = "gcs", region = "example-region1", gcp = { projectId = "example-project" } }
    error_message = "the chart uses GCS in the infra root's project and region"
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).additionalServiceAccountAnnotations == { "iam.gke.io/gcp-service-account" = "union-dataplane-system@example-project.iam.gserviceaccount.com" }
    error_message = "the platform service accounts carry the Workload Identity annotation for the infra root's Google service account"
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).userRoleAnnotationKey == "iam.gke.io/gcp-service-account" && yamldecode(helm_release.dataplane.values[1]).userRoleAnnotationValue == "union-dataplane-system@example-project.iam.gserviceaccount.com"
    error_message = "task pods' service accounts carry the same Workload Identity annotation"
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).config.k8s.plugins.k8s["gpu-device-node-label"] == "cloud.google.com/gke-accelerator"
    error_message = "GPU tasks must select nodes by GKE's accelerator label"
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).fluentbit.enabled == false
    error_message = "the chart's fluentbit is off: GKE's Cloud Logging already ships the logs"
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).global == { AUTH_CLIENT_ID = "example-client-id", CONTROLPLANE_HOST = "union.example.com", ORG_NAME = "example-org" }
    error_message = "the client ID, control plane host and org name are set exactly as given"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).secrets == { admin = { create = false } }
    error_message = "the chart must not create union-secret-auth: you create it, so the client secret stays out of state"
  }
  assert {
    condition     = helm_release.dataplane.set_sensitive == null && alltrue([for v in helm_release.dataplane.values : !strcontains(v, "clientSecret")])
    error_message = "no client secret is passed to the release"
  }

  # Provider blocks cannot be read by an assert, so this assert reads main.tf itself: both providers reach the cluster
  # at https:// plus the bare endpoint IP, with the infra CA, through gke-gcloud-auth-plugin.
  assert {
    condition = alltrue([
      for pattern in [
        "(?m)^ +host += \"https://\\$\\{sensitive\\(local\\.infra\\.cluster_endpoint\\)\\}\"$",
        "(?m)^ +cluster_ca_certificate += base64decode\\(sensitive\\(local\\.infra\\.cluster_ca_certificate\\)\\)$",
        "(?m)^ +command += \"gke-gcloud-auth-plugin\"$",
      ] : length(regexall(pattern, file("${path.module}/main.tf"))) == 2
    ])
    error_message = "the kubernetes and helm providers must both use https://<cluster_endpoint>, the cluster CA and gke-gcloud-auth-plugin"
  }
}

# Another scenario's state (and another namespace): every infra-derived value follows it, none is fixed in this root.
run "follows_the_infra_state" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in merge(jsondecode(file("tests/fixtures/gpu.json")), { namespace = "union-example" }) : k => v if v != null }
    }
  }

  assert {
    condition     = helm_release.dataplane.namespace == "union-example"
    error_message = "the release goes into the infra root's namespace output, where the Workload Identity bindings point"
  }
  assert {
    condition     = helm_release.dataplane.values[0] == jsondecode(file("tests/fixtures/gpu.json")).helm_values
    error_message = "the infra values (buckets, cluster name) are the state's"
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).userRoleAnnotationValue == "union-gpu-system@example-project.iam.gserviceaccount.com" && values(yamldecode(helm_release.dataplane.values[1]).additionalServiceAccountAnnotations) == ["union-gpu-system@example-project.iam.gserviceaccount.com"]
    error_message = "the Workload Identity annotations name the state's Google service account"
  }
}

run "rejects_empty_client_id" {
  command = plan

  variables {
    union_client_id = " "
  }

  expect_failures = [var.union_client_id]
}

run "rejects_control_plane_host_with_scheme" {
  command = plan

  variables {
    union_control_plane_host = "https://union.example.com"
  }

  expect_failures = [var.union_control_plane_host]
}

run "rejects_bad_org_name" {
  command = plan

  variables {
    union_org_name = "Example_Org"
  }

  expect_failures = [var.union_org_name]
}

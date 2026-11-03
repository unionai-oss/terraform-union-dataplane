# Credential-free mock plans against fixtures of the infra root's outputs: configuration behaviour only.
mock_provider "kubernetes" {}
mock_provider "helm" {}

# The infra root's outputs for the minimal example: instance principals, no Terraform-created storage key
# (checks.sh keeps the keys equal to ../infra/outputs.tf, infra/tests/contract.tftest.hcl the values).
override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = { for k, v in jsondecode(file("tests/fixtures/minimal.json")) : k => v if v != null }
  }
}

variables {
  union_client_id          = "example-client-id"
  union_control_plane_host = "dataplane.example.com"
  union_org_name           = "acme"
}

run "defaults" {
  command = plan

  assert {
    condition     = helm_release.dataplane.chart == "dataplane" && helm_release.dataplane.version == "2026.10.1" && helm_release.dataplane.repository == "https://unionai.github.io/helm-charts"
    error_message = "the release must be the Union dataplane chart at the pinned version."
  }
  assert {
    condition     = helm_release.dataplane.namespace == "union" && output.namespace == "union"
    error_message = "the release goes in the union namespace, where the auth Secret is."
  }

  # The chart ships no OCI overlay, so the infra helm_values are the whole cloud layer, under the org settings.
  assert {
    condition     = length(helm_release.dataplane.values) == 2 && helm_release.dataplane.values[0] == jsondecode(file("tests/fixtures/minimal.json")).helm_values
    error_message = "the first values layer must be the infra root's helm_values, unchanged."
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).global == { AUTH_CLIENT_ID = "example-client-id", CONTROLPLANE_HOST = "dataplane.example.com", ORG_NAME = "acme" }
    error_message = "the second layer must carry the client ID, control plane host and org name."
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).global.CLUSTER_NAME == jsondecode(file("tests/fixtures/minimal.json")).cluster_name
    error_message = "global.CLUSTER_NAME must reach the release from infra."
  }

  # The OAuth client secret stays out of Terraform: the chart uses the union-secret-auth Secret the operator creates.
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).secrets.admin.create == false
    error_message = "secrets.admin.create must be false: the operator creates union-secret-auth."
  }
  assert {
    condition     = alltrue([for v in helm_release.dataplane.values : !strcontains(v, "clientSecret")])
    error_message = "no values layer may carry a client secret."
  }

  assert {
    condition     = local.exec_args == ["ce", "cluster", "generate-token", "--cluster-id", "ocid1.cluster.oc1.iad.example", "--region", "us-ashburn-1"]
    error_message = "the providers must get their token from `oci ce cluster generate-token` for the infra cluster and region."
  }

  assert {
    condition     = length(kubernetes_secret_v1.storage_credentials) == 0
    error_message = "without an infra storage key the operator creates storage-credentials; Terraform must not."
  }
}

run "storage_secret_from_infra_key" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/static-credentials.json")) : k => v if v != null }
    }
  }

  assert {
    condition     = length(kubernetes_secret_v1.storage_credentials) == 1 && kubernetes_secret_v1.storage_credentials[0].metadata[0].name == "storage-credentials" && kubernetes_secret_v1.storage_credentials[0].metadata[0].namespace == helm_release.dataplane.namespace
    error_message = "with an infra storage key the Secret storage-credentials must be created in the release namespace."
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).storage.credentialsSecretRef.name == kubernetes_secret_v1.storage_credentials[0].metadata[0].name
    error_message = "the chart must read the Secret this root creates."
  }
  assert {
    condition     = nonsensitive(kubernetes_secret_v1.storage_credentials[0].data.access_key_id) == "example-access-key-id" && nonsensitive(kubernetes_secret_v1.storage_credentials[0].data.secret_key) == "example-secret-key"
    error_message = "the Secret must hold the infra root's access key and secret key under the chart's key names."
  }
}

run "rejects_control_plane_host_with_scheme" {
  command = plan

  variables {
    union_control_plane_host = "https://dataplane.example.com"
  }

  expect_failures = [var.union_control_plane_host]
}

run "rejects_bad_org_name" {
  command = plan

  variables {
    union_org_name = "Not_Valid"
  }

  expect_failures = [var.union_org_name]
}

run "rejects_empty_client_id" {
  command = plan

  variables {
    union_client_id = " "
  }

  expect_failures = [var.union_client_id]
}

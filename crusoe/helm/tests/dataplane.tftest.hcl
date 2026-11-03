# Credential-free mock plans: configuration behaviour only, nothing is provisioned.
mock_provider "kubernetes" {}
mock_provider "helm" {}

# The infra root's outputs for examples/crusoe/infra/basic.tfvars (checks.sh keeps the keys equal to
# ../infra/outputs.tf; ../infra/tests/contract.tftest.hcl keeps the values equal to what infra plans).
# Nulls are dropped because Terraform stores no root output whose value is null, so remote state has no such key.
override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
  }
}

variables {
  union_client_id          = "example-client-id"
  union_control_plane_host = "acme.union.ai"
  union_org_name           = "acme"
}

run "release_gets_the_infra_cloud_layer" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/gpu.json")) : k => v if v != null }
    }
  }

  assert {
    condition     = helm_release.dataplane.values[0] == local.infra.helm_values
    error_message = "The release's first values document must be the infra helm_values, unchanged."
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).clusterName == "union-gpu"
    error_message = "The release must follow the scenario's infra helm_values."
  }
}

run "defaults" {
  command = plan

  # The storage-credentials secret is read by three parties that must agree on its name and two field names: the
  # chart's credentialsSecretRef and fluent-bit's env (both in the infra helm_values;
  # ../infra/tests/dataplane.tftest.hcl checks them), and the Secret itself.
  assert {
    condition     = kubernetes_secret_v1.storage_credentials.metadata[0].name == yamldecode(local.infra.helm_values).storage.credentialsSecretRef.name && kubernetes_secret_v1.storage_credentials.metadata[0].namespace == helm_release.dataplane.namespace
    error_message = "The Secret must be the one the infra helm_values reference, in the release's namespace."
  }
  assert {
    condition     = toset([for e in yamldecode(local.infra.helm_values).fluentbit.env : e.valueFrom.secretKeyRef.name]) == toset([kubernetes_secret_v1.storage_credentials.metadata[0].name]) && toset([for e in yamldecode(local.infra.helm_values).fluentbit.env : e.valueFrom.secretKeyRef.key]) == toset(keys(kubernetes_secret_v1.storage_credentials.data))
    error_message = "fluent-bit must read exactly the Secret's name and keys."
  }
  assert {
    condition     = toset(keys(kubernetes_secret_v1.storage_credentials.data)) == toset(["access_key_id", "secret_key"]) && kubernetes_secret_v1.storage_credentials.data["access_key_id"] == "example-access-key-id" && nonsensitive(kubernetes_secret_v1.storage_credentials.data["secret_key"]) == "example-secret-access-key"
    error_message = "The Secret must hold the infra storage key ID in access_key_id and its secret in secret_key."
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).global == { AUTH_CLIENT_ID = "example-client-id", CONTROLPLANE_HOST = "acme.union.ai", ORG_NAME = "acme" }
    error_message = "The client ID, control plane host and org must reach the chart's globals."
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).secrets == { admin = { create = false } }
    error_message = "The chart must not create the auth Secret: you create union-secret-auth, so the client secret stays out of state."
  }
  assert {
    condition     = !strcontains(join("\n", helm_release.dataplane.values), "clientSecret")
    error_message = "No client secret may be passed to the chart."
  }

  assert {
    condition     = helm_release.dataplane.chart == "dataplane" && helm_release.dataplane.version == "2026.10.1" && helm_release.dataplane.repository == "https://unionai.github.io/helm-charts"
    error_message = "The dataplane chart must be pinned to an exact version."
  }
  assert {
    condition     = helm_release.dataplane.name == "union" && helm_release.dataplane.namespace == "union"
    error_message = "The release is union in namespace union, where the auth Secret is created."
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
    union_org_name = "Acme_Org"
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

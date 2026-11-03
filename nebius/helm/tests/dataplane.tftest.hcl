# Credential-free mock plans against fixtures of the infra root's outputs: configuration behaviour only.
mock_provider "kubernetes" {}
mock_provider "helm" {}

# The infra root's outputs for the basic example (checks.sh keeps the keys equal to ../infra/outputs.tf,
# infra/tests/contract.tftest.hcl the values).
override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
  }
}

variables {
  union_client_id = "example-client-id"
  union_org_name  = "acme"
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

  # The chart ships no Nebius overlay, so the infra helm_values are the whole cloud layer, under the org settings.
  assert {
    condition     = length(helm_release.dataplane.values) == 2 && helm_release.dataplane.values[0] == jsondecode(file("tests/fixtures/basic.json")).helm_values
    error_message = "the first values layer must be the infra root's helm_values, unchanged."
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).global.AUTH_CLIENT_ID == "example-client-id" && yamldecode(helm_release.dataplane.values[1]).global.ORG_NAME == "acme"
    error_message = "the second layer must carry the client ID and org name."
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).clusterName == jsondecode(file("tests/fixtures/basic.json")).cluster_name
    error_message = "clusterName must reach the release from infra."
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).global.CONTROLPLANE_HOST == "acme.union.ai"
    error_message = "the control plane host must default to <org>.union.ai."
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
    condition     = local.exec_args == ["mk8s", "v1", "cluster", "get-token", "--format", "json"]
    error_message = "the providers must get their token from `nebius mk8s v1 cluster get-token`."
  }

  assert {
    condition     = kubernetes_secret_v1.storage_credentials.metadata[0].name == "storage-credentials" && kubernetes_secret_v1.storage_credentials.metadata[0].namespace == helm_release.dataplane.namespace
    error_message = "the Secret storage-credentials must be created in the release namespace."
  }
  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).storage.credentialsSecretRef.name == kubernetes_secret_v1.storage_credentials.metadata[0].name
    error_message = "the chart must read the Secret this root creates."
  }
  assert {
    condition     = nonsensitive(kubernetes_secret_v1.storage_credentials.data.access_key_id) == "example-access-key-id" && nonsensitive(kubernetes_secret_v1.storage_credentials.data.secret_key) == "example-secret-key"
    error_message = "the Secret must hold the infra root's access key and secret key under the chart's key names."
  }
}

run "control_plane_host_overrides_default" {
  command = plan

  variables {
    union_control_plane_host = "dataplane.example.com"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[1]).global.CONTROLPLANE_HOST == "dataplane.example.com"
    error_message = "an explicit control plane host must win over <org>.union.ai."
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

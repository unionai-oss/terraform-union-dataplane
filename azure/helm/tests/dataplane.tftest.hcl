# The Union dataplane release (dataplane.tf): the chart, its values in order, and the inputs from Union.

mock_provider "helm" {}
mock_provider "kubernetes" {}

# The infra root's outputs for a data plane without the optional pools (checks.sh keeps the keys equal to infra/outputs.tf, and
# infra/tests/contract.tftest.hcl the values). Null values are dropped, as state drops them: Terraform does not store
# a root output whose value is null, so the helm root never sees one.
override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
  }
}

# Placeholders: the organization, its control plane and the client ID come from Union (README, Apply).
variables {
  union_client_id          = "example-client-id"
  union_control_plane_host = "union.example.com"
  union_org_name           = "acme"
}

# Every check on these inputs shares one plan: each run block re-plans the whole root against the mocks.
run "dataplane_release" {
  command = plan

  assert {
    condition     = helm_release.dataplane.chart == "dataplane" && helm_release.dataplane.version == "2026.10.1" && helm_release.dataplane.repository == "https://unionai.github.io/helm-charts"
    error_message = "the Union dataplane chart is pinned"
  }

  assert {
    condition     = helm_release.dataplane.name == "union" && helm_release.dataplane.namespace == "union" && helm_release.dataplane.namespace == local.infra.namespace && helm_release.dataplane.create_namespace
    error_message = "the release goes into the namespace the infra root bound the federated credentials to"
  }

  assert {
    condition     = helm_release.dataplane.timeout == 900
    error_message = "the release waits up to 15 minutes"
  }

  # Later values documents win, so the order is: the Azure layer, the infrastructure the infra root built, then what
  # only Union knows.
  assert {
    condition     = length(helm_release.dataplane.values) == 3
    error_message = "three values documents"
  }

  assert {
    condition     = helm_release.dataplane.values[1] == local.infra.helm_values && yamldecode(helm_release.dataplane.values[1]).global.CLUSTER_NAME == "union-dataplane"
    error_message = "the infra root's helm_values come second"
  }

  assert {
    condition = (
      yamldecode(helm_release.dataplane.values[0]).provider == "azure" &&
      yamldecode(helm_release.dataplane.values[0]).storage.provider == "custom" &&
      yamldecode(helm_release.dataplane.values[0]).storage.bucketName == "union-dataplane-metadata" &&
      yamldecode(helm_release.dataplane.values[0]).storage.custom.container == local.infra.bucket_name &&
      yamldecode(helm_release.dataplane.values[0]).storage.custom.stow == { kind = "azure", config = { account = "uniondataplaneabcd1234" } }
    )
    error_message = "storage is the infra root's metadata container through stow's Azure kind, with no account key"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).config.operator.clusterData.metadataBucketPrefix == "abfs://${local.infra.bucket_name}@${local.infra.storage_account_name}.dfs.core.windows.net"
    error_message = "the metadata prefix is the abfs:// Data Lake path of the container"
  }

  assert {
    condition = (
      yamldecode(helm_release.dataplane.values[0]).config.k8s.plugins.k8s["default-env-vars"] == [{ AZURE_STORAGE_ACCOUNT_NAME = local.infra.storage_account_name }] &&
      yamldecode(helm_release.dataplane.values[0]).config.k8s.plugins.k8s["default-labels"] == [{ "azure.workload.identity/use" = "true" }]
    )
    error_message = "task pods know the storage account and carry the workload identity label"
  }

  # The infra root federated the backend identity to the chart's union-system service account and the worker identity
  # to the task pods' service accounts; these annotations and labels are what makes pods use them.
  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).additionalServiceAccountAnnotations == { "azure.workload.identity/client-id" = "example-backend-client-id" }
    error_message = "the chart's service accounts carry the backend identity's client ID"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).userRoleAnnotationKey == "azure.workload.identity/client-id" && yamldecode(helm_release.dataplane.values[0]).userRoleAnnotationValue == local.infra.worker_client_id
    error_message = "task pods' service accounts carry the worker identity's client ID"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).additionalPodLabels == { "azure.workload.identity/use" = "true" }
    error_message = "the chart's pods are labelled for the workload identity webhook"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[0]).namespace_mapping.template == "{{ `{{ domain }}` }}"
    error_message = "multi-namespace mode maps tasks to one namespace per domain, the set worker_namespaces federates"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[2]).global == { AUTH_CLIENT_ID = "example-client-id", CONTROLPLANE_HOST = "union.example.com", ORG_NAME = "acme" }
    error_message = "the last values document carries the client ID, control plane host and org name"
  }

  # The client secret is never in Terraform: the chart reads the union-secret-auth Secret you create.
  assert {
    condition     = yamldecode(helm_release.dataplane.values[2]).secrets.admin.create == false
    error_message = "secrets.admin.create = false: the chart uses the existing union-secret-auth Secret"
  }

  assert {
    condition     = length(coalesce(helm_release.dataplane.set_sensitive, [])) == 0 && !strcontains(join("\n", helm_release.dataplane.values), "client_secret:")
    error_message = "no secret is passed to the release"
  }
}

# union_org_name and union_control_plane_host are both required now, which replaces the old check that a host is
# given with an org.
run "rejects_bad_org_name" {
  command = plan

  variables {
    union_org_name = "Acme_Org"
  }

  expect_failures = [var.union_org_name]
}

run "rejects_control_plane_host_with_scheme" {
  command = plan

  variables {
    union_control_plane_host = "https://union.example.com"
  }

  expect_failures = [var.union_control_plane_host]
}

run "rejects_empty_client_id" {
  command = plan

  variables {
    union_client_id = ""
  }

  expect_failures = [var.union_client_id]
}

run "rejects_client_id_with_spaces" {
  command = plan

  variables {
    union_client_id = "example client id"
  }

  expect_failures = [var.union_client_id]
}

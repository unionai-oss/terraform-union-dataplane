# Dataplane release (dataplane.tf): the chart, its values in order, the auth Secret left to you, and the validations
# of this root's inputs. Plans against mock providers and a fixture of the infra root's outputs; nothing is created.

mock_provider "kubernetes" {}
mock_provider "helm" {}

# The infra root's outputs for the minimal example (infra's contract.tftest.hcl keeps the fixture equal to them).
# Null outputs are left out, as Terraform leaves them out of state.
override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = { for k, v in jsondecode(file("tests/fixtures/minimal.json")) : k => v if v != null }
  }
}

variables {
  union_client_id          = "example-client-id"
  union_control_plane_host = "example.union.ai"
  union_org_name           = "example"
}

run "release" {
  command = plan

  assert {
    condition = (
      helm_release.dataplane.chart == "dataplane" && helm_release.dataplane.version == "2026.10.1" &&
      helm_release.dataplane.repository == "https://unionai.github.io/helm-charts" &&
      helm_release.dataplane.name == "union" && helm_release.dataplane.namespace == "union" && helm_release.dataplane.create_namespace
    )
    error_message = "the dataplane chart 2026.10.1 as release union in namespace union"
  }

  # Helm merges the values in order, later ones winning.
  assert {
    condition     = length(helm_release.dataplane.values) == 3 && helm_release.dataplane.values[0] == local.infra.helm_values
    error_message = "the values are the infra root's helm_values, then the AWS keys, then this root's settings"
  }

  assert {
    condition = (
      yamldecode(helm_release.dataplane.values[1]).provider == "aws" &&
      yamldecode(helm_release.dataplane.values[1]).storage == { provider = "aws", authType = "iam", region = "us-east-2" }
    )
    error_message = "the chart uses S3 in the infra root's region through IRSA, with AWS as the cloud provider"
  }

  # Without these the chart's pods and the task pods get no AWS credentials.
  assert {
    condition = (
      yamldecode(helm_release.dataplane.values[1]).additionalServiceAccountAnnotations == { "eks.amazonaws.com/role-arn" = "arn:aws:iam::example-account-id:role/test-dp-union-system" } &&
      yamldecode(helm_release.dataplane.values[1]).userRoleAnnotationKey == "eks.amazonaws.com/role-arn" &&
      yamldecode(helm_release.dataplane.values[1]).userRoleAnnotationValue == "arn:aws:iam::example-account-id:role/test-dp-union-system"
    )
    error_message = "the chart's service accounts and the task pods' accounts are annotated with the infra root's IRSA role"
  }

  assert {
    condition = (
      yamldecode(helm_release.dataplane.values[0]).global.CLUSTER_NAME == "test-dp" &&
      yamldecode(helm_release.dataplane.values[0]).global.METADATA_BUCKET == "test-dp-abcd1234-metadata" &&
      yamldecode(helm_release.dataplane.values[0]).global.FAST_REGISTRATION_BUCKET == "test-dp-abcd1234-fast-reg" &&
      yamldecode(helm_release.dataplane.values[0]).global.AWS_ACCOUNT_ID == "example-account-id" &&
      yamldecode(helm_release.dataplane.values[0]).imageBuilder.registryName == "test-dp"
    )
    error_message = "the infra root's cluster, buckets, account and registry reach the chart"
  }

  assert {
    condition = yamldecode(helm_release.dataplane.values[2]).global == {
      AUTH_CLIENT_ID    = "example-client-id"
      CONTROLPLANE_HOST = "example.union.ai"
      ORG_NAME          = "example"
    }
    error_message = "the client ID, control plane host and org reach the chart exactly as given"
  }

  assert {
    condition     = yamldecode(helm_release.dataplane.values[2]).secrets == { admin = { create = false } }
    error_message = "the chart does not create the auth Secret: you create union-secret-auth, so the secret stays out of state"
  }

  assert {
    condition     = alltrue([for v in helm_release.dataplane.values : !strcontains(lower(v), "clientsecret")]) && length(helm_release.dataplane.set_sensitive == null ? [] : helm_release.dataplane.set_sensitive) == 0
    error_message = "no client secret is passed to the chart"
  }
}

run "rejects_control_plane_host_with_scheme" {
  command = plan

  variables {
    union_control_plane_host = "https://example.union.ai"
  }

  expect_failures = [var.union_control_plane_host]
}

run "rejects_control_plane_host_with_port" {
  command = plan

  variables {
    union_control_plane_host = "example.union.ai:443"
  }

  expect_failures = [var.union_control_plane_host]
}

run "rejects_uppercase_org_name" {
  command = plan

  variables {
    union_org_name = "Example"
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

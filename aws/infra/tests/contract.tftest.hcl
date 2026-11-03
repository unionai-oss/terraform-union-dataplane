# The helm root's tests read this root's outputs from the fixtures in ../helm/tests/fixtures (one per example). This
# file plans this root with each example's inputs and requires every output to equal the fixture, so the helm tests
# cannot pass against outputs this root does not produce. checks.sh separately requires the fixture keys to be exactly
# the output names.
#
# Values that are unknown until apply (cluster endpoint and CA, ARNs, the registry URL, the name suffix) are overridden
# with the fixture's own values, so for those this checks the wiring (which attribute reaches which output) and not
# the value. The two fixtures share them; they are read from minimal.json.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["zone-a", "zone-b", "zone-c"]
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::example-account-id:role/test"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "random" {}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = jsondecode(file("../helm/tests/fixtures/minimal.json")).account_id
  }
}

override_module {
  target = module.eks
  outputs = {
    cluster_certificate_authority_data = jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_ca_certificate
    cluster_endpoint                   = jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_endpoint
    cluster_name                       = jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_name
    oidc_provider                      = "oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
    oidc_provider_arn                  = jsondecode(file("../helm/tests/fixtures/minimal.json")).oidc_provider_arn
  }
}

override_resource {
  target          = random_id.suffix
  override_during = plan
  values = {
    hex = "abcd1234"
  }
}

override_resource {
  target          = aws_iam_role.union_system
  override_during = plan
  values = {
    arn = jsondecode(file("../helm/tests/fixtures/minimal.json")).iam_role_arn
  }
}

override_resource {
  target          = aws_ecr_repository.image_builder
  override_during = plan
  values = {
    repository_url = jsondecode(file("../helm/tests/fixtures/minimal.json")).ecr_repository_url
  }
}

variables {
  name   = "test-dp"
  region = "us-east-2"
}

run "minimal" {
  command = plan

  # jsonencode on both sides: == between a list and a tuple of the same values is false.
  assert {
    condition = jsonencode({
      account_id               = output.account_id
      bucket_name              = output.bucket_name
      cluster_ca_certificate   = output.cluster_ca_certificate
      cluster_endpoint         = output.cluster_endpoint
      cluster_name             = output.cluster_name
      ecr_repository_name      = output.ecr_repository_name
      ecr_repository_url       = output.ecr_repository_url
      fast_registration_bucket = output.fast_registration_bucket
      gpu_node_pool            = output.gpu_node_pool
      gpu_node_selector        = output.gpu_node_selector
      helm_values              = output.helm_values
      iam_role_arn             = output.iam_role_arn
      kubeconfig_command       = output.kubeconfig_command
      oidc_provider_arn        = output.oidc_provider_arn
      region                   = output.region
    }) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")))
    error_message = "the outputs of the minimal example differ from ../helm/tests/fixtures/minimal.json"
  }
}

run "gpu_and_spot" {
  command = plan

  variables {
    worker_node_pool = { enabled = true, capacity_type = "SPOT", desired_size = 2 }
    gpu_node_pool    = { enabled = true, instance_types = ["g5.2xlarge"] }
  }

  assert {
    condition = jsonencode({
      account_id               = output.account_id
      bucket_name              = output.bucket_name
      cluster_ca_certificate   = output.cluster_ca_certificate
      cluster_endpoint         = output.cluster_endpoint
      cluster_name             = output.cluster_name
      ecr_repository_name      = output.ecr_repository_name
      ecr_repository_url       = output.ecr_repository_url
      fast_registration_bucket = output.fast_registration_bucket
      gpu_node_pool            = output.gpu_node_pool
      gpu_node_selector        = output.gpu_node_selector
      helm_values              = output.helm_values
      iam_role_arn             = output.iam_role_arn
      kubeconfig_command       = output.kubeconfig_command
      oidc_provider_arn        = output.oidc_provider_arn
      region                   = output.region
    }) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu-and-spot.json")))
    error_message = "the outputs of the gpu-and-spot example differ from ../helm/tests/fixtures/gpu-and-spot.json"
  }
}

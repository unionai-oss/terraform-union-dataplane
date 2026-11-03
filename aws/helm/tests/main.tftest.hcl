# The helm base (main.tf): the NVIDIA device plugin, which follows the infra root's GPU pool. Plans against mock
# providers and a fixture of the infra root's outputs; nothing is created.

mock_provider "kubernetes" {}
mock_provider "helm" {}

# The infra root's outputs (infra's contract.tftest.hcl keeps the fixture equal to them). Null outputs are left out,
# as Terraform leaves them out of state.
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

run "gpu_pool_installs_the_device_plugin" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/gpu-and-spot.json")) : k => v if v != null }
    }
  }

  assert {
    condition     = helm_release.nvidia_device_plugin[0].chart == "nvidia-device-plugin" && helm_release.nvidia_device_plugin[0].version == "0.20.1" && helm_release.nvidia_device_plugin[0].repository == "https://nvidia.github.io/k8s-device-plugin"
    error_message = "the NVIDIA device plugin chart is pinned"
  }

  # The label and taint of the GPU pool in the infra root's main.tf (its base tests check them there); the label is
  # infra's gpu_node_selector output, which its contract.tftest.hcl ties to the fixture.
  assert {
    condition = (
      yamldecode(helm_release.nvidia_device_plugin[0].values[0]).nodeSelector == { "node-pool" = "gpu" } &&
      yamldecode(helm_release.nvidia_device_plugin[0].values[0]).tolerations == [{ key = "nvidia.com/gpu", operator = "Exists", effect = "NoSchedule" }]
    )
    error_message = "the plugin runs on the GPU nodes only and tolerates their taint"
  }
}

run "no_gpu_pool" {
  command = plan

  # Every check on these inputs shares one plan: each run block re-plans the whole root.
  assert {
    condition     = length(helm_release.nvidia_device_plugin) == 0
    error_message = "no device plugin without the GPU pool"
  }

  # Provider configuration is not readable from a test, so read main.tf: both providers take the endpoint, the CA and
  # the exec token command from the infra outputs.
  assert {
    condition = alltrue([
      for argument in [
        "host += local\\.infra\\.cluster_endpoint",
        "cluster_ca_certificate = base64decode\\(local\\.infra\\.cluster_ca_certificate\\)",
        "args += \\[\"eks\", \"get-token\", \"--cluster-name\", local\\.infra\\.cluster_name, \"--region\", local\\.infra\\.region\\]",
      ] :
      length(regexall("\\n +${argument}\\n", file("${path.module}/main.tf"))) == 2
    ])
    error_message = "the kubernetes and helm providers reach the infra root's cluster with an aws eks get-token exec"
  }
}

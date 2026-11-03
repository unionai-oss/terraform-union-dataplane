# The helm base (main.tf): the provider configuration and the NVIDIA device plugin.

mock_provider "helm" {}
mock_provider "kubernetes" {}

# The infra root's outputs for a data plane with the GPU pool (checks.sh keeps the keys equal to infra/outputs.tf, and
# infra/tests/contract.tftest.hcl the values). Null values are dropped, as state drops them: Terraform does not store
# a root output whose value is null, so the helm root never sees one.
override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = { for k, v in jsondecode(file("tests/fixtures/gpu.json")) : k => v if v != null }
  }
}

# Placeholders: the organization, its control plane and the client ID come from Union (README, Apply).
variables {
  union_client_id          = "example-client-id"
  union_control_plane_host = "union.example.com"
  union_org_name           = "acme"
}

# Every check on these inputs shares one plan: each run block re-plans the whole root against the mocks.
run "providers_and_device_plugin_for_the_gpu_pool" {
  command = plan

  # terraform test cannot read a provider's configuration, so its exec arguments are checked in main.tf's text: both
  # providers sign in with kubelogin through az login, for the server application infra reads from the cluster.
  assert {
    condition     = length(regexall("(?m)^ +command += \"kubelogin\"$", file("${path.module}/main.tf"))) == 2
    error_message = "the kubernetes and helm providers both run kubelogin"
  }

  assert {
    condition     = length(regexall("(?m)^ +args += \\[\"get-token\", \"--login\", \"azurecli\", \"--server-id\", sensitive\\(local\\.infra\\.kubelogin_server_id\\)\\]$", file("${path.module}/main.tf"))) == 2
    error_message = "both get a token through az login for the cluster's Entra server application"
  }

  assert {
    condition     = helm_release.nvidia_device_plugin[0].chart == "nvidia-device-plugin" && helm_release.nvidia_device_plugin[0].version == "0.20.1" && helm_release.nvidia_device_plugin[0].repository == "https://nvidia.github.io/k8s-device-plugin"
    error_message = "the NVIDIA device plugin chart is pinned"
  }

  # The label and taint of the GPU pool in the infra root's main.tf (its base tests check them there); the label is
  # infra's gpu_node_selector output, which its contract.tftest.hcl ties to the fixture.
  assert {
    condition = (
      yamldecode(helm_release.nvidia_device_plugin[0].values[0]).nodeSelector["node-pool"] == "gpu" &&
      yamldecode(helm_release.nvidia_device_plugin[0].values[0]).tolerations[0].key == "nvidia.com/gpu" &&
      yamldecode(helm_release.nvidia_device_plugin[0].values[0]).tolerations[0].operator == "Exists" &&
      yamldecode(helm_release.nvidia_device_plugin[0].values[0]).tolerations[0].effect == "NoSchedule"
    )
    error_message = "the plugin runs on the GPU nodes only and tolerates their taint"
  }
}

run "no_device_plugin_without_gpu_pool" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
    }
  }

  assert {
    condition     = length(helm_release.nvidia_device_plugin) == 0
    error_message = "no device plugin without the GPU pool"
  }
}

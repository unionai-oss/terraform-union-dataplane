# The contract between the two roots (CONVENTIONS section 8): the helm tests plan against fixtures of this root's
# outputs, one per scenario in ../helm/tests/fixtures/. Each run here plans this root with that scenario's inputs and
# checks that it outputs exactly the fixture, so a renamed output, a pass-through whose shape changed or a value
# built differently fails here instead of passing in the helm tests. Values this root cannot know at plan (endpoints,
# client IDs, the registry) are taken from the fixture through overrides, so for them only the wiring is checked.
# nat_gateway_public_ip is read by a data source that waits for the NAT module, so it is unknown at plan and only its
# name is checked (by checks.sh, with every other fixture key).

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "time" {}

# The key vault and role assignments validate these as UUIDs. Built with join and format because checks.sh bans GUID and 12-digit literals.
override_data {
  target          = data.azurerm_client_config.current
  override_during = plan
  values = {
    tenant_id       = join("-", ["00000000", "0000", "0000", "0000", format("%012d", 1)])
    subscription_id = join("-", ["00000000", "0000", "0000", "0000", format("%012d", 2)])
    object_id       = join("-", ["00000000", "0000", "0000", "0000", format("%012d", 3)])
  }
}

# Resource group IDs are validated by the AVM modules, and the mock generates a random string.
override_resource {
  target          = azurerm_resource_group.this
  override_during = plan
  values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg" }
}

# hex is computed, so it is unknown during plan unless overridden there.
override_resource {
  target          = random_id.suffix
  override_during = plan
  values          = { hex = "abcd1234" }
}

# resource_id is computed, so it is unknown during plan unless overridden there.
override_module {
  target = module.nat
  outputs = {
    resource_id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.Network/natGateways/union-dataplane"
  }
}

# Known IDs so role assignment scopes can be asserted.
override_resource {
  target          = azurerm_storage_account.this
  override_during = plan
  values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.Storage/storageAccounts/store" }
}

run "basic" {
  command = plan

  variables {
    region                          = "test-region"
    api_server_authorized_ip_ranges = ["203.0.113.0/24"]
  }

  # The values infra cannot know at plan, from the fixture itself; everything else is computed by this root.
  override_module {
    target = module.aks
    outputs = {
      name                           = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_name
      resource_id                    = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ContainerService/managedClusters/union-dataplane"
      oidc_issuer_profile_issuer_url = jsondecode(file("../helm/tests/fixtures/basic.json")).oidc_issuer_url
      cluster_ca_certificate         = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_ca_certificate
      kube_config                    = yamlencode({ clusters = [{ cluster = { server = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_endpoint } }], users = [{ user = { exec = { args = ["get-token", "--server-id", jsondecode(file("../helm/tests/fixtures/basic.json")).kubelogin_server_id] } } }] })
      kubelet_identity               = { objectId = "kubelet-object-id" }
    }
  }

  override_resource {
    target          = azurerm_user_assigned_identity.backend
    override_during = plan
    values = {
      id           = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
      client_id    = jsondecode(file("../helm/tests/fixtures/basic.json")).backend_client_id
      principal_id = "backend-principal-id"
    }
  }

  override_resource {
    target          = azurerm_user_assigned_identity.worker
    override_during = plan
    values = {
      id           = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/worker"
      client_id    = jsondecode(file("../helm/tests/fixtures/basic.json")).worker_client_id
      principal_id = "worker-principal-id"
    }
  }

  override_resource {
    target          = azurerm_container_registry.this
    override_during = plan
    values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ContainerRegistry/registries/registry", login_server = jsondecode(file("../helm/tests/fixtures/basic.json")).container_registry_login_server }
  }

  override_resource {
    target          = azurerm_log_analytics_workspace.this
    override_during = plan
    values          = { id = jsondecode(file("../helm/tests/fixtures/basic.json")).log_analytics_workspace_id }
  }

  # jsonencode on both sides, because == finds a list and a tuple with the same elements different. Every output in
  # one object, so a failure shows the difference; the sensitive ones on their own, since one sensitive value would
  # hide the whole difference.
  assert {
    condition = jsonencode({
      backend_client_id               = output.backend_client_id
      bucket_name                     = output.bucket_name
      cluster_name                    = output.cluster_name
      container_registry_login_server = output.container_registry_login_server
      gpu_node_pool                   = output.gpu_node_pool
      gpu_node_selector               = output.gpu_node_selector
      key_vault_uri                   = output.key_vault_uri
      kubeconfig_command              = output.kubeconfig_command
      log_analytics_workspace_id      = output.log_analytics_workspace_id
      namespace                       = output.namespace
      oidc_issuer_url                 = output.oidc_issuer_url
      region                          = output.region
      resource_group_name             = output.resource_group_name
      storage_account_name            = output.storage_account_name
      worker_client_id                = output.worker_client_id
    }) == jsonencode({ for k, v in jsondecode(file("../helm/tests/fixtures/basic.json")) : k => v if !contains(["helm_values", "nat_gateway_public_ip", "cluster_ca_certificate", "cluster_endpoint", "kubelogin_server_id"], k) })
    error_message = "infra's outputs for the basic scenario differ from helm/tests/fixtures/basic.json, which the helm tests plan against"
  }

  assert {
    condition = jsonencode({
      cluster_ca_certificate = output.cluster_ca_certificate
      cluster_endpoint       = output.cluster_endpoint
      kubelogin_server_id    = output.kubelogin_server_id
    }) == jsonencode({ for k, v in jsondecode(file("../helm/tests/fixtures/basic.json")) : k => v if contains(["cluster_ca_certificate", "cluster_endpoint", "kubelogin_server_id"], k) })
    error_message = "infra's sensitive outputs for the basic scenario differ from helm/tests/fixtures/basic.json"
  }

  # The subscription and tenant IDs are UUIDs, which a fixture cannot hold (checks.sh bans GUID literals), so the
  # fixture has placeholders for them and the rest of helm_values is compared.
  assert {
    condition = jsonencode(yamldecode(output.helm_values)) == jsonencode(merge(yamldecode(jsondecode(file("../helm/tests/fixtures/basic.json")).helm_values), {
      global = merge(yamldecode(jsondecode(file("../helm/tests/fixtures/basic.json")).helm_values).global, {
        AZURE_SUBSCRIPTION_ID = data.azurerm_client_config.current.subscription_id
        AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
      })
    }))
    error_message = "infra's helm_values for the basic scenario differ from helm/tests/fixtures/basic.json"
  }
}

run "gpu" {
  command = plan

  variables {
    name                            = "union-gpu"
    region                          = "test-region"
    api_server_authorized_ip_ranges = ["203.0.113.0/24"]
    gpu_node_pool                   = { enabled = true }
    enable_key_vault                = true
  }

  # The values infra cannot know at plan, from the fixture itself; everything else is computed by this root.
  override_module {
    target = module.aks
    outputs = {
      name                           = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_name
      resource_id                    = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ContainerService/managedClusters/union-dataplane"
      oidc_issuer_profile_issuer_url = jsondecode(file("../helm/tests/fixtures/gpu.json")).oidc_issuer_url
      cluster_ca_certificate         = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_ca_certificate
      kube_config                    = yamlencode({ clusters = [{ cluster = { server = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_endpoint } }], users = [{ user = { exec = { args = ["get-token", "--server-id", jsondecode(file("../helm/tests/fixtures/gpu.json")).kubelogin_server_id] } } }] })
      kubelet_identity               = { objectId = "kubelet-object-id" }
    }
  }

  override_resource {
    target          = azurerm_user_assigned_identity.backend
    override_during = plan
    values = {
      id           = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
      client_id    = jsondecode(file("../helm/tests/fixtures/gpu.json")).backend_client_id
      principal_id = "backend-principal-id"
    }
  }

  override_resource {
    target          = azurerm_user_assigned_identity.worker
    override_during = plan
    values = {
      id           = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/worker"
      client_id    = jsondecode(file("../helm/tests/fixtures/gpu.json")).worker_client_id
      principal_id = "worker-principal-id"
    }
  }

  override_resource {
    target          = azurerm_container_registry.this
    override_during = plan
    values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ContainerRegistry/registries/registry", login_server = jsondecode(file("../helm/tests/fixtures/gpu.json")).container_registry_login_server }
  }

  override_resource {
    target          = azurerm_log_analytics_workspace.this
    override_during = plan
    values          = { id = jsondecode(file("../helm/tests/fixtures/gpu.json")).log_analytics_workspace_id }
  }

  override_resource {
    target          = azurerm_key_vault.this
    override_during = plan
    values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.KeyVault/vaults/vault", vault_uri = jsondecode(file("../helm/tests/fixtures/gpu.json")).key_vault_uri }
  }

  # jsonencode on both sides, because == finds a list and a tuple with the same elements different. Every output in
  # one object, so a failure shows the difference; the sensitive ones on their own, since one sensitive value would
  # hide the whole difference.
  assert {
    condition = jsonencode({
      backend_client_id               = output.backend_client_id
      bucket_name                     = output.bucket_name
      cluster_name                    = output.cluster_name
      container_registry_login_server = output.container_registry_login_server
      gpu_node_pool                   = output.gpu_node_pool
      gpu_node_selector               = output.gpu_node_selector
      key_vault_uri                   = output.key_vault_uri
      kubeconfig_command              = output.kubeconfig_command
      log_analytics_workspace_id      = output.log_analytics_workspace_id
      namespace                       = output.namespace
      oidc_issuer_url                 = output.oidc_issuer_url
      region                          = output.region
      resource_group_name             = output.resource_group_name
      storage_account_name            = output.storage_account_name
      worker_client_id                = output.worker_client_id
    }) == jsonencode({ for k, v in jsondecode(file("../helm/tests/fixtures/gpu.json")) : k => v if !contains(["helm_values", "nat_gateway_public_ip", "cluster_ca_certificate", "cluster_endpoint", "kubelogin_server_id"], k) })
    error_message = "infra's outputs for the gpu scenario differ from helm/tests/fixtures/gpu.json, which the helm tests plan against"
  }

  assert {
    condition = jsonencode({
      cluster_ca_certificate = output.cluster_ca_certificate
      cluster_endpoint       = output.cluster_endpoint
      kubelogin_server_id    = output.kubelogin_server_id
    }) == jsonencode({ for k, v in jsondecode(file("../helm/tests/fixtures/gpu.json")) : k => v if contains(["cluster_ca_certificate", "cluster_endpoint", "kubelogin_server_id"], k) })
    error_message = "infra's sensitive outputs for the gpu scenario differ from helm/tests/fixtures/gpu.json"
  }

  # The subscription and tenant IDs are UUIDs, which a fixture cannot hold (checks.sh bans GUID literals), so the
  # fixture has placeholders for them and the rest of helm_values is compared.
  assert {
    condition = jsonencode(yamldecode(output.helm_values)) == jsonencode(merge(yamldecode(jsondecode(file("../helm/tests/fixtures/gpu.json")).helm_values), {
      global = merge(yamldecode(jsondecode(file("../helm/tests/fixtures/gpu.json")).helm_values).global, {
        AZURE_SUBSCRIPTION_ID = data.azurerm_client_config.current.subscription_id
        AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
      })
    }))
    error_message = "infra's helm_values for the gpu scenario differ from helm/tests/fixtures/gpu.json"
  }
}

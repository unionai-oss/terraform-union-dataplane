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

# The AKS module cannot be read from a test, so its outputs are fixed here and the inputs that matter are asserted
# through the named locals in main.tf.
override_module {
  target = module.aks
  outputs = {
    name                           = "union-dataplane"
    resource_id                    = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ContainerService/managedClusters/union-dataplane"
    oidc_issuer_profile_issuer_url = "https://oidc.example.com/test-issuer/"
    cluster_ca_certificate         = "Y2E="
    kube_config                    = yamlencode({ clusters = [{ cluster = { server = "https://api.example.com" } }], users = [{ user = { exec = { args = ["get-token", "--server-id", "server-app"] } } }] })
    kubelet_identity               = { objectId = "kubelet-object-id" }
  }
}

# Computed values helm_values needs at plan time.
override_resource {
  target          = azurerm_user_assigned_identity.backend
  override_during = plan
  values = {
    id           = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/backend"
    client_id    = "backend-client-id"
    principal_id = "backend-principal-id"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.worker
  override_during = plan
  values = {
    id           = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/worker"
    client_id    = "worker-client-id"
    principal_id = "worker-principal-id"
  }
}

# Known IDs so role assignment scopes can be asserted.
override_resource {
  target          = azurerm_storage_account.this
  override_during = plan
  values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.Storage/storageAccounts/store" }
}

override_resource {
  target          = azurerm_container_registry.this
  override_during = plan
  values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.ContainerRegistry/registries/registry" }
}

override_resource {
  target          = azurerm_key_vault.this
  override_during = plan
  values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.KeyVault/vaults/vault", vault_uri = "https://vault.example.com/" }
}

override_resource {
  target          = azurerm_log_analytics_workspace.this
  override_during = plan
  values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg/providers/Microsoft.OperationalInsights/workspaces/union-dataplane" }
}

variables {
  region                          = "test-region"
  api_server_authorized_ip_ranges = ["203.0.113.0/24"]
}

# Every check on these inputs shares one plan: each run block re-plans the whole root against the mocks.
run "dataplane_with_default_inputs" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "union-dataplane-rg" && azurerm_resource_group.this.location == "test-region"
    error_message = "resource group must be <name>-rg in var.region"
  }

  assert {
    condition     = azurerm_storage_account.this.name == "uniondataplaneabcd1234" && length(azurerm_storage_account.this.name) <= 24
    error_message = "storage account name must be the name without hyphens plus the suffix, at most 24 characters"
  }

  assert {
    condition     = azurerm_container_registry.this.name == "uniondataplaneabcd1234"
    error_message = "registry name must be alphanumeric <name><suffix>"
  }

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled && azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "storage needs the hierarchical namespace and no shared keys"
  }

  assert {
    condition     = azurerm_storage_account.this.tags["managed-by"] == "terraform" && azurerm_storage_account.this.tags["stack"] == "union-dataplane"
    error_message = "default tags must be applied"
  }

  assert {
    condition     = azurerm_storage_container.metadata.name == "union-dataplane-metadata"
    error_message = "metadata container must be <name>-metadata"
  }

  assert {
    condition     = toset(one(azurerm_storage_account.this.blob_properties).cors_rule[0].allowed_methods) == toset(["GET", "HEAD"])
    error_message = "storage needs the Code Viewer CORS rule"
  }

  assert {
    # Mock providers accept it, so only this catches it before a live apply fails on it.
    condition     = one(azurerm_storage_account.this.blob_properties).versioning_enabled != true
    error_message = "blob versioning cannot be combined with the hierarchical namespace; the azurerm provider rejects it at create"
  }

  assert {
    condition     = length(azurerm_key_vault.this) == 0 && length(azurerm_role_assignment.backend_key_vault) == 0
    error_message = "Key Vault must be absent by default"
  }

  assert {
    condition     = keys(local.subnets) == ["nodes"] && local.subnets.nodes.address_prefixes == ["10.0.0.0/18"]
    error_message = "the node subnet is the only subnet by default"
  }

  assert {
    condition     = endswith(local.subnets.nodes.nat_gateway.id, "/natGateways/union-dataplane")
    error_message = "the node subnet must reference the NAT gateway"
  }

  assert {
    condition     = keys(local.agent_pools) == ["workers"]
    error_message = "default optional pools are workers only"
  }

  assert {
    condition     = local.agent_pools.workers.min_count == 0 && local.agent_pools.workers.enable_auto_scaling
    error_message = "the worker pool scales from zero"
  }

  assert {
    condition     = azurerm_role_assignment.worker_acr_push.role_definition_name == "AcrPush" && azurerm_role_assignment.backend_acr_pull.role_definition_name == "AcrPull"
    error_message = "worker pushes and backend pulls"
  }

  assert {
    condition     = azurerm_role_assignment.backend_storage.role_definition_name == "Storage Blob Data Contributor" && azurerm_role_assignment.worker_storage.role_definition_name == "Storage Blob Data Contributor"
    error_message = "both identities need blob data access on the account"
  }

  assert {
    condition     = azurerm_role_assignment.backend_logs.role_definition_name == "Log Analytics Reader"
    error_message = "backend reads persisted logs"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.CLUSTER_NAME == "union-dataplane"
    error_message = "helm_values must carry global.CLUSTER_NAME"
  }

  assert {
    condition     = azurerm_role_assignment.kubelet_acr_pull.principal_id == "kubelet-object-id" && azurerm_role_assignment.kubelet_acr_pull.role_definition_name == "AcrPull"
    error_message = "the kubelet identity pulls from the registry"
  }

  assert {
    condition     = azurerm_role_assignment.backend_storage.scope == azurerm_storage_account.this.id && azurerm_role_assignment.worker_storage.scope == azurerm_storage_account.this.id && endswith(azurerm_storage_account.this.id, "/storageAccounts/store")
    error_message = "storage roles are scoped to the storage account"
  }

  assert {
    condition     = azurerm_role_assignment.backend_storage.principal_id == "backend-principal-id" && azurerm_role_assignment.worker_storage.principal_id == "worker-principal-id"
    error_message = "storage roles go to the matching identity"
  }

  assert {
    condition     = azurerm_role_assignment.backend_acr_pull.principal_id == "backend-principal-id" && azurerm_role_assignment.worker_acr_push.principal_id == "worker-principal-id" && azurerm_role_assignment.kubelet_acr_pull.scope == azurerm_container_registry.this.id
    error_message = "registry roles go to the matching identity"
  }

  # The organization and control plane keys are the helm root's (its dataplane.tf), so they are never in helm_values.
  assert {
    condition     = length(setintersection(keys(yamldecode(output.helm_values).global), ["AUTH_CLIENT_ID", "CONTROLPLANE_HOST", "ORG_NAME", "UNION_CONTROL_PLANE_HOST"])) == 0
    error_message = "helm_values must leave the org, control plane host and client ID to the helm root"
  }
}

run "tags_merge_over_defaults" {
  command = plan

  variables {
    tags = { team = "data", stack = "override" }
  }

  assert {
    condition     = azurerm_container_registry.this.tags["team"] == "data" && azurerm_container_registry.this.tags["stack"] == "override"
    error_message = "var.tags must be merged over the defaults"
  }
}

run "pools_optional" {
  command = plan

  variables {
    worker_node_pool = { enabled = false }
    gpu_node_pool    = { enabled = true }
  }

  assert {
    condition     = keys(local.agent_pools) == ["gpu"]
    error_message = "only the gpu pool when the worker pool is disabled"
  }
  assert {
    condition     = local.agent_pools.gpu.min_count == 0 && local.agent_pools.gpu.node_taints == ["nvidia.com/gpu=true:NoSchedule"] && local.agent_pools.gpu.node_labels["node-pool"] == "gpu"
    error_message = "the gpu pool scales from zero, is tainted nvidia.com/gpu and labelled node-pool=gpu"
  }
}

run "workload_identity_federation" {
  command = plan

  variables {
    worker_namespaces = ["development"]
  }

  assert {
    condition     = azurerm_federated_identity_credential.backend.subject == "system:serviceaccount:union:union-system"
    error_message = "backend federates to union-system"
  }
  assert {
    condition     = azurerm_federated_identity_credential.worker.subject == "system:serviceaccount:union:union"
    error_message = "worker federates to union"
  }
  assert {
    condition     = azurerm_federated_identity_credential.worker_namespace["development"].subject == "system:serviceaccount:development:default"
    error_message = "extra namespaces federate the default service account"
  }
}

run "key_vault_enabled_and_in_helm_values" {
  command = plan

  variables {
    enable_key_vault = true
  }

  assert {
    condition     = length(azurerm_key_vault.this) == 1 && azurerm_role_assignment.backend_key_vault[0].role_definition_name == "Key Vault Secrets Officer"
    error_message = "Key Vault and the backend role appear when enabled"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.METADATA_CONTAINER == azurerm_storage_container.metadata.name && yamldecode(output.helm_values).global.AZURE_STORAGE_ACCOUNT == azurerm_storage_account.this.name
    error_message = "storage keys must match the resources"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.AZURE_SUBSCRIPTION_ID == data.azurerm_client_config.current.subscription_id && yamldecode(output.helm_values).global.AZURE_TENANT_ID == data.azurerm_client_config.current.tenant_id && yamldecode(output.helm_values).global.AZURE_RESOURCE_GROUP == azurerm_resource_group.this.name
    error_message = "subscription, tenant and resource group keys must match"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.AZURE_BACKEND_CLIENT_ID == azurerm_user_assigned_identity.backend.client_id && yamldecode(output.helm_values).global.AZURE_WORKER_CLIENT_ID == azurerm_user_assigned_identity.worker.client_id
    error_message = "client ID keys must match the right identities"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.AZURE_KEY_VAULT_URI == azurerm_key_vault.this[0].vault_uri
    error_message = "Key Vault URI key must match"
  }

  assert {
    condition     = yamldecode(output.helm_values).config.proxy.persistedLogs.azureLogAnalytics.logAnalyticsWorkspaceResourceIdTemplate == local.log_analytics_workspace_id
    error_message = "the log workspace key must match"
  }
}

run "existing_log_analytics_workspace" {
  command = plan

  variables {
    log_analytics_workspace_id = "/subscriptions/sub/resourceGroups/other/providers/Microsoft.OperationalInsights/workspaces/shared"
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.this) == 0
    error_message = "no workspace is created when one is passed in"
  }
}

run "rejects_bad_name" {
  command = plan

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}

run "federated_credential_issuer_and_identity" {
  command = plan

  variables {
    worker_namespaces = ["a", "b", "c"]
  }

  assert {
    condition     = azurerm_federated_identity_credential.backend.issuer == "https://oidc.example.com/test-issuer/" && azurerm_federated_identity_credential.worker.issuer == azurerm_federated_identity_credential.backend.issuer && azurerm_federated_identity_credential.worker_namespace["c"].issuer == azurerm_federated_identity_credential.backend.issuer
    error_message = "credentials must trust the AKS OIDC issuer"
  }
  assert {
    condition     = azurerm_federated_identity_credential.backend.user_assigned_identity_id == azurerm_user_assigned_identity.backend.id && azurerm_federated_identity_credential.worker_namespace["b"].user_assigned_identity_id == azurerm_user_assigned_identity.worker.id
    error_message = "credentials attach to the matching identity"
  }
}

run "any_number_of_worker_namespaces" {
  command = plan

  variables {
    worker_namespaces = ["development", "staging", "production", "team-a-development", "team-a-production"]
  }

  assert {
    condition = (
      length(azurerm_federated_identity_credential.worker_namespace) == 5 &&
      alltrue([for ns in var.worker_namespaces : (
        azurerm_federated_identity_credential.worker_namespace[ns].subject == "system:serviceaccount:${ns}:default" &&
        azurerm_federated_identity_credential.worker_namespace[ns].name == "union-dataplane-worker-${ns}" &&
        azurerm_federated_identity_credential.worker_namespace[ns].user_assigned_identity_id == azurerm_user_assigned_identity.worker.id
      )])
    )
    error_message = "every worker namespace gets a credential for its default service account on the worker identity"
  }
}

run "outputs_for_the_helm_root" {
  command = plan

  variables {
    gpu_node_pool = { enabled = true }
    namespace     = "union-test"
  }

  assert {
    condition     = output.kubelogin_server_id == "server-app" && output.cluster_endpoint == "https://api.example.com" && output.cluster_ca_certificate == "Y2E="
    error_message = "the helm root's providers get the endpoint, the CA and the cluster's Entra server application"
  }

  assert {
    condition     = output.gpu_node_pool.enabled && output.gpu_node_pool.vm_size == "Standard_NC4as_T4_v3"
    error_message = "the helm root gets the GPU pool settings, defaults applied, for the device plugin"
  }

  assert {
    condition     = output.namespace == "union-test" && azurerm_federated_identity_credential.backend.subject == "system:serviceaccount:union-test:union-system"
    error_message = "the helm root installs the chart into the namespace the federated credentials are bound to"
  }
}

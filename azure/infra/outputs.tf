# Every value the helm root reads is an output here, under one name (CONVENTIONS section 3). terraform_remote_state
# drops the sensitive mark, so the helm root wraps the sensitive ones in sensitive() itself.

output "backend_client_id" {
  description = "Client ID of the backend identity (global.AZURE_BACKEND_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.backend.client_id
}

output "bucket_name" {
  description = "Metadata blob container name (global.METADATA_CONTAINER)."
  value       = azurerm_storage_container.metadata.name
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.aks.cluster_ca_certificate
  sensitive   = true
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL."
  value       = yamldecode(module.aks.kube_config).clusters[0].cluster.server
  sensitive   = true
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.name
}

output "container_registry_login_server" {
  description = "ACR login server for task images and the image builder."
  value       = azurerm_container_registry.this.login_server
}

output "gpu_node_pool" {
  description = "The gpu_node_pool input with its defaults applied, for the helm root (the device plugin follows enabled)."
  value       = var.gpu_node_pool
}

output "gpu_node_selector" {
  description = "Node labels that select the GPU pool's nodes, for the helm root (the NVIDIA device plugin's nodeSelector)."
  value       = local.gpu_node_selector
}

output "helm_values" {
  description = "Infrastructure keys for the dataplane chart, layered over its values.azure.yaml by the helm root. CLUSTER_NAME is the AKS cluster name; use the name you registered with Union if it differs. The organization and control plane keys are the helm root's."
  value = yamlencode({
    global = merge({
      CLUSTER_NAME            = module.aks.name
      METADATA_CONTAINER      = azurerm_storage_container.metadata.name
      AZURE_STORAGE_ACCOUNT   = azurerm_storage_account.this.name
      AZURE_SUBSCRIPTION_ID   = data.azurerm_client_config.current.subscription_id
      AZURE_TENANT_ID         = data.azurerm_client_config.current.tenant_id
      AZURE_RESOURCE_GROUP    = azurerm_resource_group.this.name
      AZURE_BACKEND_CLIENT_ID = azurerm_user_assigned_identity.backend.client_id
      AZURE_WORKER_CLIENT_ID  = azurerm_user_assigned_identity.worker.client_id
      },
      # The Key Vault URI is only known when the optional vault exists.
      var.enable_key_vault ? { AZURE_KEY_VAULT_URI = azurerm_key_vault.this[0].vault_uri } : {}
    )
    # Explicit ID so a reused workspace in another resource group works too.
    config = {
      proxy = {
        persistedLogs = {
          sourceType = "AzureLogAnalytics"
          azureLogAnalytics = {
            logAnalyticsWorkspaceResourceIdTemplate = local.log_analytics_workspace_id
          }
        }
      }
    }
    # Chart >= 2026.8.0 already sets this; older charts need it.
    fluentbit = { enabled = false }
  })
}

output "key_vault_uri" {
  description = "Key Vault URI (global.AZURE_KEY_VAULT_URI); null unless enable_key_vault is true."
  value       = one(azurerm_key_vault.this[*].vault_uri)
}

output "kubeconfig_command" {
  description = "Command that writes a kubeconfig entry for the cluster. Entra ID sign-in needs kubelogin on PATH."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${module.aks.name} && kubelogin convert-kubeconfig -l azurecli"
}

output "kubelogin_server_id" {
  description = "Entra server application of the cluster, the --server-id the helm root passes to kubelogin get-token."
  # From module.aks.kube_config, which is sensitive.
  value     = local.kubelogin_server_id
  sensitive = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace holding persisted task logs."
  value       = local.log_analytics_workspace_id
}

output "namespace" {
  description = "Namespace the dataplane chart is installed into (the namespace input), which the federated credentials are bound to. Create the union-secret-auth Secret here before the helm apply."
  value       = var.namespace
}

output "nat_gateway_public_ip" {
  description = "Static egress IP of the node subnet; use it to allowlist the cluster."
  value       = data.azurerm_public_ip.nat.ip_address
}

output "oidc_issuer_url" {
  description = "AKS OIDC issuer URL used by the federated credentials."
  value       = module.aks.oidc_issuer_profile_issuer_url
}

output "region" {
  description = "Azure location."
  value       = azurerm_resource_group.this.location
}

output "resource_group_name" {
  description = "Resource group holding all resources (global.AZURE_RESOURCE_GROUP)."
  value       = azurerm_resource_group.this.name
}

output "storage_account_name" {
  description = "Storage account name (global.AZURE_STORAGE_ACCOUNT)."
  value       = azurerm_storage_account.this.name
}

output "worker_client_id" {
  description = "Client ID of the worker identity (global.AZURE_WORKER_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.worker.client_id
}

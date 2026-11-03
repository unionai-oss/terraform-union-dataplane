# The Union dataplane layer on top of the base in main.tf: object storage, the image registry, and the workload
# identities the Union Helm chart's service accounts use. The helm root installs the chart (its dataplane.tf).

locals {
  # Extra subnets for the product layer, merged into the VNet in main.tf. The dataplane needs none; the sibling
  # terraform-flyte/azure adds its delegated Postgres subnet here, so main.tf stays the same text in both repos.
  product_subnets = {}
}

# Blob storage must have the hierarchical namespace (Data Lake Gen2): Union uses abfs://.
# prevent_destroy cannot be switched off by a variable and would make `terraform destroy` of a trial data plane
# impossible; the README tells you to protect the account with a resource lock in production.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_account" "this" {
  name                            = local.unique_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = var.storage_shared_key_enabled
  min_tls_version                 = "TLS1_2"
  tags                            = local.tags

  # CORS for the Code Viewer in the Union UI. No versioning_enabled, although the other clouds version the metadata
  # bucket: Azure does not support blob versioning with the hierarchical namespace, and the azurerm provider fails
  # the create with "`versioning_enabled` can't be true when `is_hns_enabled` is true".
  blob_properties {
    cors_rule {
      allowed_origins    = var.cors_origins
      allowed_methods    = ["GET", "HEAD"]
      allowed_headers    = ["*"]
      exposed_headers    = ["ETag"]
      max_age_in_seconds = 3600
    }
  }
}

# Created through the management API (storage_account_id), so no account key is needed. One container serves
# metadata and fast registration: the Azure values file has a single METADATA_CONTAINER.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_container" "metadata" {
  name                  = "${var.name}-metadata"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_container_registry" "this" {
  name                = local.unique_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_key_vault" "this" {
  # Optional per the docs; off by default.
  count = var.enable_key_vault ? 1 : 0

  name                       = local.unique_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = local.tags
}

# backend: operator, propeller, clusterresourcesync (service account union-system).
resource "azurerm_user_assigned_identity" "backend" {
  name                = "${var.name}-backend"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

# worker: task pods (service account union).
resource "azurerm_user_assigned_identity" "worker" {
  name                = "${var.name}-worker"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "backend" {
  name                      = "${var.name}-backend"
  user_assigned_identity_id = azurerm_user_assigned_identity.backend.id
  issuer                    = module.aks.oidc_issuer_profile_issuer_url
  subject                   = "system:serviceaccount:${var.namespace}:union-system"
  audience                  = ["api://AzureADTokenExchange"]
}

resource "azurerm_federated_identity_credential" "worker" {
  name                      = "${var.name}-worker"
  user_assigned_identity_id = azurerm_user_assigned_identity.worker.id
  issuer                    = module.aks.oidc_issuer_profile_issuer_url
  subject                   = "system:serviceaccount:${var.namespace}:union"
  audience                  = ["api://AzureADTokenExchange"]
}

# Multi-namespace mode (low_privilege: false) runs tasks as `default` in each project-domain namespace.
# Azure rejects concurrent writes to one identity's federated credentials. No ordering is needed here: the azurerm
# provider takes a lock on the parent identity around every create, update and delete of a federated credential.
resource "azurerm_federated_identity_credential" "worker_namespace" {
  for_each = toset(var.worker_namespaces)

  name                      = "${var.name}-worker-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.worker.id
  issuer                    = module.aks.oidc_issuer_profile_issuer_url
  subject                   = "system:serviceaccount:${each.key}:default"
  audience                  = ["api://AzureADTokenExchange"]
}

resource "azurerm_role_assignment" "backend_storage" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

resource "azurerm_role_assignment" "worker_storage" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
}

# Without this the UI log pane stays empty. When log_analytics_workspace_id points at a workspace owned
# elsewhere, the applier needs roleAssignments/write there.
resource "azurerm_role_assignment" "backend_logs" {
  scope                = local.log_analytics_workspace_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

resource "azurerm_role_assignment" "backend_key_vault" {
  # Only exists with the optional Key Vault.
  count = var.enable_key_vault ? 1 : 0

  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

# Registry: backend pulls, worker pushes (Image Builder), kubelet pulls onto nodes.
resource "azurerm_role_assignment" "backend_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

resource "azurerm_role_assignment" "worker_acr_push" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.worker.principal_id
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity.objectId
}

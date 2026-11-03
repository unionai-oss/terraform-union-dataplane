# Union data plane on Azure (self-managed)

Terraform for a self-managed Union.ai data plane on Azure: the Azure infrastructure it needs, and the Union
`dataplane` Helm chart on top. Standalone: nothing here references another cloud folder.

Two root modules, applied in order: `infra/` creates everything through the Azure API, then `helm/` installs the
chart through the Kubernetes API. `helm/` reads all it needs from the state of `infra/`; nothing is copied between the
two by hand. The one manual step between them is Union's: registering the cluster and storing its credential (Apply).

Validated (fmt, validate, tflint, terraform test with mock providers) but not yet applied live.

## What it creates

`infra/`:

| File | What |
|---|---|
| `main.tf` | The base, identical to `terraform-flyte/azure/infra`: resource group `<name>-rg`; VNet and private node subnet (Azure Verified Module `avm-res-network-virtualnetwork`); NAT gateway with a static public IP, attached to the node subnet (`avm-res-network-natgateway`, because the VNet module has none); AKS (`avm-res-containerservice-managedcluster`) with Azure CNI overlay, OIDC issuer, workload identity, Entra ID with Azure RBAC and no local accounts, Container Insights (with the data collection rule `MSCI-<name>` that sends its streams to the workspace, associated with the cluster), a `system` pool (3 non-burstable nodes), an optional `workers` pool and an optional `gpu` pool (both scale from zero; the GPU pool is tainted `nvidia.com/gpu=true:NoSchedule` and labelled `node-pool=gpu`); Log Analytics workspace; the cluster-admin role assignments, and a 120 s wait after them so the role reaches the Kubernetes API before the infra apply returns. |
| `dataplane.tf` | `local.product_subnets` (empty: the sibling adds a subnet there, see below); storage account with hierarchical namespace (Data Lake Gen2), private metadata container and the Code Viewer CORS rule; Azure Container Registry; optional Key Vault (RBAC mode); user-assigned identities `<name>-backend` and `<name>-worker` with federated credentials (`union-system` and `union` in the `namespace` namespace, plus `default` in each `worker_namespaces` entry); role assignments below. |
| `variables.tf`, `outputs.tf` | Inputs and outputs, including the `helm_values` YAML string the helm root installs the chart with. |

`helm/`:

| File | What |
|---|---|
| `main.tf` | The helm base, identical to `terraform-flyte/azure/helm`: the remote state of `infra/`, the `kubernetes` and `helm` providers, and with `gpu_node_pool.enabled` the NVIDIA device plugin (AKS' GPU node image ships the driver; pods can request `nvidia.com/gpu` only once the plugin runs). |
| `dataplane.tf` | The Union `dataplane` chart `2026.10.1` as release `union` in the `namespace` namespace: its Azure values (storage, workload identity annotations and labels, the abfs metadata prefix), then `helm_values` from `infra/`, then the organization, control plane host and client ID. `secrets.admin.create = false`: the chart reads the `union-secret-auth` Secret you create. |

Role assignments (`infra/`): Storage Blob Data Contributor on the storage account (backend and worker); Log Analytics
Reader on the workspace (backend); Key Vault Secrets Officer (backend, only with `enable_key_vault`); AcrPull
(backend and kubelet) and AcrPush (worker) on the registry; Azure Kubernetes Service RBAC Cluster Admin on the cluster
(the identity running Terraform and `cluster_admin_principal_ids`).

Base modules: `Azure/avm-res-network-virtualnetwork/azurerm` 0.22.3,
`Azure/avm-res-network-natgateway/azurerm` 0.3.2 and `Azure/avm-res-containerservice-managedcluster/azurerm` 0.8.7.
The AVM modules create their resources through `azapi`; the storage, registry, identity and role resources use
`azurerm`. The resource group, Log Analytics workspace and role assignments are `azurerm` resources because the
modules take them as inputs. `infra/` also uses `hashicorp/time` (the wait); `helm/` declares no Azure provider.

Requirements implemented, from the Union self-managed Azure docs: infrastructure sections 1-9 and deploy
configuration, node pools, private subnets and NAT, registry, workload identity, large overlay pod CIDR, non-burstable
system nodes; the marketplace page is used only where the self-managed page is silent (ACR, 200 GiB OS disks,
registry roles).

## Prerequisites

- Terraform 1.11 or newer (validated with 1.16.6) and the Azure CLI signed in (`az login`).
- `ARM_SUBSCRIPTION_ID` set for the infra apply (the provider requires it); other `ARM_*` variables work too, e.g.
  for a service principal. Credentials are never Terraform variables.
- Owner, or Contributor plus User Access Administrator, on the subscription: Contributor alone cannot create role
  assignments. The identity that runs the infra apply becomes cluster admin; run the helm apply as that identity (or
  add yours to `cluster_admin_principal_ids`).
- Resource providers registered on the subscription (`Microsoft.ContainerService`, `ContainerRegistry`, `Storage`,
  `Network`, `OperationalInsights`, `ManagedIdentity`, and `KeyVault` if used), and vCPU quota for the pools.
- For the helm apply: [kubelogin](https://azure.github.io/kubelogin/) on `PATH`, and a route to the AKS API endpoint.
  The `kubernetes` and `helm` providers run `kubelogin get-token --login azurecli --server-id <server application>`,
  reusing the `az login` session, with the server application from the `kubelogin_server_id` output, so no cluster
  credential and no Entra application ID is written into the configuration. In CI, set `ARM_*` and sign in with
  `az login --service-principal`. The endpoint is public (nodes are private) but never open to any address by
  default: `api_server_authorized_ip_ranges` must include the address you apply from.
- The `uctl` and `flyte` CLIs, signed in to your Union organization, for the step between the applies.

## Apply

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform -chdir=azure/infra init && terraform -chdir=azure/infra apply -var-file=../../examples/azure/infra/basic.tfvars
```

`region` has no default, and `api_server_authorized_ip_ranges` must list the addresses you reach the API from. A
second data plane in the same subscription needs a different `name`.

Then, before the helm apply, register the cluster and create the dataplane's credential
([Deploy the data plane](https://www.union.ai/docs/v2/union/deployment/selfmanaged/deploy.md)), using the
`cluster_name` output: `flyte create cluster ...`, then
`uctl selfserve provision-dataplane-resources --clusterName <cluster_name> --provider azure`. It prints a client ID
and a secret; Union does not store the secret. Put the secret in the cluster yourself, in the `namespace` output's
namespace (`union` by default), so it never reaches Terraform state:

```bash
terraform -chdir=azure/infra output -raw kubeconfig_command | sh
kubectl create namespace union
kubectl -n union create secret generic union-secret-auth \
  --from-literal=client_secret=<secret> --from-literal=app_secret=<secret>
```

Then set `union_org_name`, `union_control_plane_host` (from the data plane's Azure deploy page in the Union UI) and
`union_client_id` in the helm tfvars and apply:

```bash
terraform -chdir=azure/helm  init && terraform -chdir=azure/helm  apply -var-file=../../examples/azure/helm/basic.tfvars
```

The chart does not check that `union-secret-auth` exists: without it the apply waits out its 15-minute timeout with
crash-looping pods. `flyte get cluster` confirms the registration. Then verify logs ingestion with
`ContainerLogV2 | summarize count() by PodNamespace` in the workspace. For the image builder to authenticate to ACR
through workload identity, add `imageBuilder.authenticationType: azure` to the release and use
`container_registry_login_server`.

Examples in `../examples/azure/`, the same scenario in both roots: `basic.tfvars` (defaults) and `gpu.tfvars` (a GPU
pool, a larger worker pool and Key Vault).

## State and backends

Neither root has a `backend` block: where state lives is your choice.

1. **First run, nothing configured:** both roots use local state, and `helm/` reads `../infra/terraform.tfstate`
   (`infra_state` defaults to that).
2. **Remote state (recommended):** add a `backend.tf` to both roots, then tell `helm/` where the infra state is,
   once, in its tfvars, with the same settings as the infra backend block:
   ```hcl
   infra_state = { backend = "azurerm", config = { resource_group_name = "example-tfstate", storage_account_name = "exampletfstate", container_name = "tfstate", key = "union-dataplane/azure/infra.tfstate", use_azuread_auth = true } }
   ```
3. Give the helm runner read-only access to the infra state, and use backends with encryption at rest. Neither
   state holds the Union client secret (it is only in the `union-secret-auth` Secret).

Terraform workspaces are not supported: `helm/` reads the infra root's default workspace.

## Destroy, in reverse

```bash
terraform -chdir=azure/helm  destroy -var-file=../../examples/azure/helm/basic.tfvars
terraform -chdir=azure/infra destroy -var-file=../../examples/azure/infra/basic.tfvars
```

`helm/` first: destroying `infra/` first deletes the cluster under the releases, and the helm root then cannot reach
it; recovering takes `terraform -chdir=azure/helm state rm` of everything. The `union-secret-auth` Secret and the
namespace go with the cluster.

## Inputs

`infra/`:

| Variable | Meaning |
|---|---|
| `region` | Required. The Azure location. |
| `name` | Prefix for every resource (default `union-dataplane`). 4-54 characters: lowercase letters, digits and single hyphens, starting with a letter and not ending in a hyphen, so every name built from it is legal (the Log Analytics workspace needs 4, the AKS DNS prefix allows 54, blob containers reject `--`). Globally unique names (storage account, registry, Key Vault) are the name without hyphens, cut to 16 characters, plus a random 8-character suffix. |
| `tags` | Extra tags merged over `managed-by` and `stack`. |
| `kubernetes_version` | Default `1.34`; not checked against a live subscription, confirm with `az aks get-versions`. |
| `address_space`, `nodes_cidr`, `pod_cidr`, `service_cidr`, `dns_service_ip` | Network ranges. The pod CIDR cannot be resized in place, so keep it large. |
| `system_node_pool`, `worker_node_pool`, `gpu_node_pool` | One object per pool; the last two carry `enabled`. Worker and GPU pools scale from zero. Changing the system pool's `vm_size` or `os_disk_size_gb` is not safe to apply in place: AVM 0.8.7 has no `temporary_name_for_rotation` equivalent (the original used it). Rotate manually: add a temporary system-mode pool with `az aks nodepool add --mode System`, drain and delete the old `system` pool, recreate it with the new size, then `terraform apply` (or `terraform state rm`/`import` the pool if Terraform wants to replace it). |
| `api_server_authorized_ip_ranges`, `allow_public_api_endpoint` | CIDRs allowed to reach the Kubernetes API (the endpoint is public, nodes are private). Required: an empty list is rejected unless `allow_public_api_endpoint = true`, so the API is never open to any address by default. |
| `cluster_admin_principal_ids` | Extra Entra object IDs granted cluster-admin. |
| `cors_origins` | Default follows the self-managed page's wildcards; the marketplace page says Azure needs the exact UI origin. Override if the Code Viewer is blocked. |
| `namespace` | Namespace the chart is installed into (default `union`); the federated credentials are bound to it. |
| `enable_key_vault`, `log_analytics_workspace_id`, `worker_namespaces`, `storage_shared_key_enabled` | Optional Key Vault, reuse of an existing workspace, multi-namespace federation (any number of namespaces; Azure rejects concurrent writes to one identity's federated credentials, and the azurerm provider serializes them itself), and shared-key access (off). |

`helm/`:

| Variable | Meaning |
|---|---|
| `infra_state` | Where the infra state is (State and backends). Default: `../infra/terraform.tfstate`. |
| `union_org_name` | Required. Your Union organization (`global.ORG_NAME`). |
| `union_control_plane_host` | Required. The control plane hostname, no scheme or port (`global.CONTROLPLANE_HOST`): copy it from the data plane's Azure deploy page in the Union UI. No host is guessed. |
| `union_client_id` | Required. The client ID `uctl selfserve provision-dataplane-resources` printed (`global.AUTH_CLIENT_ID`). |

## Outputs

`infra/`: `backend_client_id`, `bucket_name` (the metadata container), `cluster_ca_certificate` (sensitive),
`cluster_endpoint` (sensitive), `cluster_name`, `container_registry_login_server`, `gpu_node_pool`, `gpu_node_selector`, `helm_values`,
`key_vault_uri`, `kubeconfig_command`, `kubelogin_server_id` (sensitive), `log_analytics_workspace_id`, `namespace`,
`nat_gateway_public_ip`, `oidc_issuer_url`, `region`, `resource_group_name`, `storage_account_name`,
`worker_client_id`. `helm/` reads `cluster_endpoint`, `cluster_ca_certificate`, `kubelogin_server_id`,
`gpu_node_pool`, `gpu_node_selector`, `helm_values`, `namespace` and the storage and identity outputs.

`helm/`: none. The release is found with `kubectl -n union get pods`, and the cluster outputs are the infra root's.

## Not covered, and why

- **Lifecycle / retention rules**: the docs only recommend them and warn that a container-wide expiry breaks
  `inputs.pb`/`outputs.pb` and caches; the safe prefix depends on your raw-data usage.
- **Metadata versioning**: the other clouds version the metadata bucket, but Azure does not support blob versioning
  on an account with the hierarchical namespace, which Union's `abfs://` paths need; the azurerm provider rejects
  `versioning_enabled` together with `is_hns_enabled`. `union-dataplane-tf` listed Azure as versioned but did not set
  it either. A test fails if versioning is turned on.
- **Separate fast-registration container**: the Azure values file has one `METADATA_CONTAINER` serving both.
- **Spot node pool**: the docs only note the spot label; no pool is specified.
- **FluentBit to Blob**: cannot use workload identity; `fluentbit.enabled: false` is emitted in `helm_values`.
- **The chart's Azure overlay** (`values.azure.yaml`): not used, because it ships without a licence file. `helm/`
  sets the keys of it this deployment needs (storage, workload identity, the abfs metadata prefix, task pod labels
  and environment, the multi-namespace mapping) from the infra outputs. Left out: the Azure portal links in task logs,
  the spot-pool selectors (no spot pool here), the GPU device labels and the Key Vault secret manager (opt-in).
- **Key Vault role for the worker identity**: the self-managed page grants only the backend identity.
- **Private cluster, Azure Monitor Private Link, storage VNet service endpoint**: only needed without outbound
  internet or on the marketplace page.
- **Availability zones**: not set on the pools or the NAT public IP, so the folder works in regions without zones.
- **Deletion protection**: the storage account and container have no `prevent_destroy` (a variable cannot toggle
  it, and it would block `terraform destroy` of a trial); add an Azure resource lock for production data.
- **Registering the cluster and creating its client** (`flyte create cluster`, `uctl selfserve provision-dataplane-resources`) and the `union-secret-auth` Secret: Union-side steps, and the Secret is kept out of Terraform state (Apply).

## Changed from union-dataplane-tf

Dropped from `union-dataplane-tf/azure`, with the reason:

- `org_name`: only named the workspace and Key Vault and fed `ORG_NAME`; names derive from `name`. It is now
  `union_org_name` in `helm/`, which with `union_control_plane_host` fills `ORG_NAME` and `CONTROLPLANE_HOST` in the
  chart values; `helm_values` carries `CLUSTER_NAME` (the AKS cluster name) as the original did.
- `resource_group_name`, `cluster_name`, `storage_account_name`, `container_registry_name`,
  `metadata_container_name`: derive from `name` and the random suffix.
- `location`, `vnet_address_space`, `node_subnet_cidr`, `create_key_vault`, `dataplane_namespace`,
  `storage_cors_origins`, `worker_pool`, `gpu_pool`, `system_node_vm_size`, `system_node_count`, `os_disk_size_gb`:
  renamed or folded into the `system_node_pool`, `worker_node_pool` and `gpu_node_pool` objects
  (`region`, `address_space`, `nodes_cidr`, `enable_key_vault`, `namespace`, `cors_origins`).
- The worker pool is now created by default (it was before) but scales from zero instead of 2 nodes, and uses
  `Standard_D8as_v5` instead of the burstable `Standard_B8as_v2`.
- Outputs `location`, `subscription_id`, `tenant_id`: `region` replaces the first; the others are inside `helm_values`.
- Local accounts were not disabled before; they are now.

## Conservative readings

- **Shared-key access** is off (marketplace behaviour, least privilege); the provider uses `storage_use_azuread = true`.
- **NAT gateway SKU** is `Standard`, not the module default `StandardV2`, which is not accepted as an AKS outbound
  gateway in every region; confirm before changing it.
- **AVM telemetry** (`enable_telemetry`) is off, so the modules send no usage data to Microsoft; `azure/modtm` is
  declared in `terraform.tf` only so the tests can mock it.
- **Kubernetes version**, **system VM size** (`Standard_D4s_v5`, non-burstable) and pool bounds are my choices where
  the docs give none.
- **Log Analytics workspace** is named `<name>`; `helm_values` pins its full resource ID so a reused workspace works.
- **Federated credentials** for `worker_namespaces` are empty by default because `low_privilege: true` is the chart default.

## Differences from the sibling repo

The sibling `terraform-flyte/azure` deploys open-source Flyte 2 on the same base, with the same two roots:
`infra/main.tf` and `helm/main.tf` are byte-identical. `module "network"` in `infra/main.tf` takes
`subnets = merge(local.subnets, local.product_subnets)`, and `local.product_subnets` is empty here (defined in
`dataplane.tf`) while the sibling's `flyte.tf` puts the delegated Postgres subnet there.

### infra

Here and not there:

- `dataplane.tf`: the Union product layer (storage, registry, Key Vault, identities).
- `tests/dataplane.tftest.hcl`: its tests.
- Variables `cors_origins`, `enable_key_vault`, `namespace`, `storage_shared_key_enabled` and `worker_namespaces`:
  the dataplane's storage, Key Vault and namespaces.
- Outputs `container_registry_login_server`, `helm_values`, `key_vault_uri`, `namespace` and `worker_client_id`:
  inputs of the Union chart.

Same name, different meaning or default:

- `bucket_name`: here the dataplane's metadata container; there the blob container holding Flyte's data.
- `name`: defaults to `union-dataplane` here and `flyte` there (CONVENTIONS section 3), with the same validation.

`tests/base.tftest.hcl` tests the shared `main.tf` and is the same file in both repositories, apart from the
sibling's mock provider for the provider only it uses. The storage account here has the hierarchical namespace (Union
uses `abfs://` with Data Lake paths) and a CORS rule; the sibling's does not.

### helm

Here and not there:

- `dataplane.tf`: the Union `dataplane` release.
- `tests/dataplane.tftest.hcl`: its tests.
- `tests/fixtures/basic.json`, `tests/fixtures/gpu.json`: the infra outputs of each example.
- Variables `union_client_id`, `union_control_plane_host` and `union_org_name`: they only fill the chart's values.

Same name, different meaning or default:

- None.

The sibling's own extras are listed in its README.

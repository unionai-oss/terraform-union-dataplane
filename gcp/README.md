# Union data plane on GCP (self-managed)

Terraform for a self-managed Union.ai data plane on GCP, in two roots applied in order: `infra/` builds the network,
the GKE cluster, the buckets, the registry and the Workload Identity service account; `helm/` installs the Union
`dataplane` chart into that cluster, reading everything it needs from the infra root's state. Standalone: nothing here
references another cloud folder.

Validated (fmt, validate, tflint, terraform test with mock providers, for both roots) but not yet applied live:
`terraform plan` against a real project and `apply` were not run, because there are no credentials.

## What it creates

`infra/`, through the Google Cloud APIs:

| File | What |
|---|---|
| `terraform.tf` | Terraform and provider pins. |
| `main.tf` | The base: API enablement; VPC and private subnet with pod and service secondary ranges, Private Google Access (`terraform-google-modules/network`); Cloud Router and Cloud NAT with dynamic port allocation (`terraform-google-modules/cloud-router`); regional private GKE cluster with Workload Identity (`terraform-google-modules/kubernetes-engine//modules/private-cluster`) and its pools: `system` (3 non-burstable nodes, one per zone), optional `worker` and `gpu` pools, and `buildkit-pool`. |
| `dataplane.tf` | Metadata bucket (versioned) and fast-registration bucket (7-day delete lifecycle), both with the Code Viewer CORS rule; Artifact Registry Docker repository; Google service account `<name>-system` with Workload Identity bindings for the `<namespace>/union-system` and `<namespace>/union` Kubernetes service accounts, bucket access (`objectAdmin`, `legacyBucketReader`, `bucketViewer`), Artifact Registry `writer` and self token creator; registry `reader` for the node service account. |
| `variables.tf`, `outputs.tf` | Inputs, and the outputs the helm root reads (including the `helm_values` YAML string). |

`helm/`, through the Kubernetes API:

| File | What |
|---|---|
| `terraform.tf` | Terraform and provider pins (`helm`, `kubernetes`; no cloud provider). |
| `main.tf` | The helm base: `data.terraform_remote_state.infra`, and the `kubernetes` and `helm` providers, which reach the cluster with `gke-gcloud-auth-plugin`. |
| `dataplane.tf` | `helm_release.dataplane`: the Union `dataplane` chart 2026.10.1 in the infra root's `namespace`, with two values layers: the infra root's `helm_values` (cluster name, buckets, service account, registry), then this root's GCP settings, built in Terraform from the infra state and the variables: GCS storage, the GKE Workload Identity annotation on the platform and task service accounts, GKE's GPU node labels, the chart's fluentbit off, and the org, control plane host and client ID. The keys were chosen after the chart's own `values.gcp.yaml`, which is not copied into this repository. `secrets.admin.create = false`: the chart reads the client secret from the `union-secret-auth` Secret you create (Apply, step 2). |
| `variables.tf`, `outputs.tf` | Inputs and outputs. |

Base modules: `terraform-google-modules/network/google` 18.3.1, `terraform-google-modules/cloud-router/google` 9.1.0
(the network module does not create a NAT) and `terraform-google-modules/kubernetes-engine/google//modules/private-cluster`
47.0.0. The GKE module declares the `kubernetes` provider for kube-system ConfigMaps (ip-masq-agent, kube-dns), but
each is behind an input this root leaves at its default, so it creates none: the infra root pins the provider for the
module and never configures it, and never talks to the Kubernetes API.

GPUs: GKE installs the NVIDIA driver (`gpu_driver_version = "DEFAULT"`) and runs the device plugin on GPU nodes itself,
so the helm root installs no device plugin, unlike aws and azure.

Requirements implemented, from the Union self-managed GCP docs: cluster, BuildKit pool, networking and IP capacity,
GCS, CORS, Artifact Registry, Workload Identity, deploy configuration, system pool sizing, private nodes, Cloud NAT
with dynamic port allocation, bucket versioning and TTL.

Logs: the persisted logs backend is GKE's default Cloud Logging. `infra/main.tf` sets neither `logging_service` nor
`logging_enabled_components`, so the module's defaults apply (Cloud Logging for Kubernetes, GKE's default system
and workload components), and the node service account the module creates has
`roles/container.defaultNodeServiceAccount`, which includes writing logs. The helm root turns the chart's own
fluentbit off for the same reason.

## Prerequisites

- Terraform 1.11 or newer (validated with 1.16.6).
- A billing-enabled project with the Cloud Resource Manager and Service Usage APIs already enabled (Terraform
  needs them to enable the rest), and permission to create the resources and grant IAM roles.
- Compute quota for the node pools in the region.
- Authentication: Application Default Credentials, e.g. `gcloud auth application-default login`
  (or `GOOGLE_APPLICATION_CREDENTIALS`, or workload identity federation). Credentials are never Terraform variables.
  The helm root uses the same credentials, through `gke-gcloud-auth-plugin --use_application_default_credentials`.
- For the helm apply only: `gke-gcloud-auth-plugin` on `PATH` (`gcloud components install gke-gcloud-auth-plugin`),
  and a route to the cluster API: the address you apply from must be in `master_authorized_networks`. The infra
  apply does not talk to the cluster.
- `kubectl`, for the Secret in Apply step 2.
- The data plane's Union client ID and secret: register the cluster with Union as in
  [Deploy the data plane](https://www.union.ai/docs/v2/union/deployment/selfmanaged/deploy.md)
  (`uctl selfserve provision-dataplane-resources`). Terraform does not create them, and Union does not store the
  secret.

## Apply

Two applies, infra then helm, with the Secret step between them. Copy the examples and fill in your own values first:
`project_id`, `region` and `master_authorized_networks` in [`../examples/gcp/infra/`](../examples/gcp/infra/),
the org, control plane host and client ID in [`../examples/gcp/helm/`](../examples/gcp/helm/).

1. The cloud resources:

   ```bash
   gcloud auth application-default login
   terraform -chdir=gcp/infra init && terraform -chdir=gcp/infra apply -var-file=../../examples/gcp/infra/basic.tfvars
   ```

2. The Union auth Secret, in the namespace the chart is installed into. Both keys hold the client secret (the chart
   reads `client_secret` and `app_secret`). It is created outside Terraform so the secret never reaches a state file:

   ```bash
   $(terraform -chdir=gcp/infra output -raw kubeconfig_command)
   NAMESPACE="$(terraform -chdir=gcp/infra output -raw namespace)"
   kubectl create namespace "$NAMESPACE"
   kubectl -n "$NAMESPACE" create secret generic union-secret-auth \
     --from-literal=client_secret="$UNION_CLIENT_SECRET" --from-literal=app_secret="$UNION_CLIENT_SECRET"
   ```

3. The chart:

   ```bash
   terraform -chdir=gcp/helm init && terraform -chdir=gcp/helm apply -var-file=../../examples/gcp/helm/basic.tfvars
   ```

The helm root reads the cluster, project, region, service account, namespace and chart values (buckets included)
from the infra state; nothing
is copied between the applies. Without the Secret the release waits out its 15-minute timeout with crashlooping pods:
the chart does not check for it.

`region` and `project_id` have no default. A second data plane in the same project needs a different `name`. A helm
plan before the infra apply fails with "No stored state was found".

## State and backends

Neither root commits a `backend` block; the choice is yours.

- **First run, nothing configured:** both roots use local state, and the helm root's default `infra_state` reads
  `../infra/terraform.tfstate`.
- **Remote state (recommended):** add a `backend.tf` to both roots, for example a `gcs` backend, and give the helm
  root the infra root's settings once, in its tfvars. This says where the state lives, like the backend block:

  ```hcl
  infra_state = { backend = "gcs", config = { bucket = "example-tfstate", prefix = "union-dataplane/gcp/infra" } }
  ```

The helm runner needs read access to the infra state: give it read-only access. Both states hold what Terraform
passes to the chart; keep them encrypted at rest with restricted access. Workspaces other than `default` are not
supported.

## Destroy

In reverse: helm first, then infra. Destroying infra first deletes the cluster under the release and leaves a helm
state that only `terraform -chdir=gcp/helm state rm` of everything clears.

```bash
terraform -chdir=gcp/helm  destroy -var-file=../../examples/gcp/helm/basic.tfvars
terraform -chdir=gcp/infra apply   -var-file=../../examples/gcp/infra/basic.tfvars -var deletion_protection=false
terraform -chdir=gcp/infra destroy -var-file=../../examples/gcp/infra/basic.tfvars -var deletion_protection=false
```

The cluster has `deletion_protection = true` by default, so turn it off with an apply before the destroy. The
namespace and the `union-secret-auth` Secret are not in Terraform; they go with the cluster.

## Inputs that matter

`infra/`:

| Variable | Meaning |
|---|---|
| `project_id`, `region` | Required. |
| `name` | Prefix for every resource (default `union-dataplane`, max 23 characters). |
| `labels` | Extra labels merged over `managed-by` and `stack`. |
| `kubernetes_version` | Minimum control-plane minor (default `1.34`; not checked against a live project, confirm it is among the three newest in your region). |
| `master_ipv4_cidr_block` | Unused `/28` for the private control plane's peering (default `172.16.0.0/28`). |
| `nodes_cidr`, `pods_cidr`, `services_cidr` | Network ranges. `/19` pods with 32 pods per node is 128 nodes; choose a `/14` before the first apply if you expect more than a few hundred. |
| `system_node_pool`, `worker_node_pool`, `gpu_node_pool`, `buildkit_node_pool` | One object per pool; the last three carry `enabled`. Autoscaled pools scale from zero. Counts are per zone. |
| `zones` | Defaults to the first three zones that a live lookup reports as UP in the region, so the set can change between plans; set `zones` to pin it, and when the GPU type is not offered in all of them. |
| `master_authorized_networks`, `allow_public_api_endpoint` | CIDRs allowed to reach the Kubernetes API (the endpoint is public, nodes are private). Required: an empty list is rejected unless `allow_public_api_endpoint = true`. Include the address the helm apply runs from. |
| `namespace` | Namespace of the chart (default `union`). The Workload Identity bindings are for its service accounts, and the helm root installs into it. |
| `cors_origins` | Default follows the docs' wildcard `https://*.unionai.cloud`; Cloud Storage may reject wildcard subdomains, in which case set `["https://<org>.hosted.unionai.cloud"]`. |
| `fast_registration_retention_days` | Days before fast-registration objects are deleted (default 7, the docs' example). |
| `deletion_protection` | Default `true`; set `false` with an apply before destroying (Destroy). |

`helm/`:

| Variable | Meaning |
|---|---|
| `union_org_name` | Required. Union organization name (`global.ORG_NAME`). |
| `union_control_plane_host` | Required. Control plane hostname without scheme or port (`global.CONTROLPLANE_HOST`). Copy it from your Union console or the Union deploy documentation; it is not derived from the org name. |
| `union_client_id` | Required. The data plane's client ID (`global.AUTH_CLIENT_ID`). Its secret is the `union-secret-auth` Secret, not an input. |
| `infra_state` | Where the infra state is (State and backends). Default: `../infra/terraform.tfstate`. |

## Outputs

`infra/`: `artifact_registry_path`, `artifact_registry_repository`, `bucket_name` (metadata),
`cluster_ca_certificate`, `cluster_endpoint` (an IP address, no scheme), `cluster_name`, `fast_registration_bucket`,
`helm_values`, `kubeconfig_command`, `namespace`, `node_service_account_email`, `project_id`, `region`,
`service_account_email`. The helm root reads `cluster_endpoint`, `cluster_ca_certificate`, `helm_values`,
`namespace`, `project_id`, `region` and `service_account_email` from the state; `helm_values` carries `global.CLUSTER_NAME` as the
GKE cluster name, the buckets, project, region, service account and registry, and no Union org settings.

`helm/`: `chart_version`, `namespace`.

## Add-ons

None. The Tailscale and MCP add-ons are terraform-flyte's: the data plane serves no endpoint of its own, and Union
hosts its own MCP.

## Not covered, and why

- **Data retention beyond the fast-registration TTL**: the docs give no values apart from the 7-day example. The
  metadata bucket is versioned and never expires; add noncurrent-version rules per the Data retention page. No
  Artifact Registry cleanup policy either.
- **Monitoring node pool and pool-aware pod tuning**: described as optional tuning, with no machine types given.
- **Per-prefix conditional project binding**: per-bucket grants are used, the docs' alternative.
- **NodeLocal DNS Cache, CoreDNS scaling, vCPU quota requests, executor limits**: cluster, Helm or console tasks.
- **Secret Manager access**: belongs to the BYOC (UI-driven) install, not the self-managed one.
- **The rest of the chart's GCP overlay** (`values.gcp.yaml`): Cloud Console task-log links, Cloud Logging as the
  operator's persisted-log source (it needs `roles/logging.viewer`, which the infra root does not grant), and the Secret
  Manager identity. Add them to `local.dataplane_values` in `helm/dataplane.tf` if you need them.
- **The Union auth Secret**: created by you (Apply, step 2), so the client secret is in no Terraform state.

## Changed from union-dataplane-tf

Dropped from `union-dataplane-tf/gcp`, with the reason:

- `single_bucket`, `bucket_prefix`: two buckets with random-suffixed names (CONVENTIONS section 3) replace them.
- `gsa_name`, `artifact_registry_repository`, `cluster_name`: all derive from `name`.
- `release_channel`: fixed to `REGULAR`.
- `system_machine_type`, `system_nodes_per_zone`, `worker_pool_enabled`, `worker_machine_type`,
  `worker_max_nodes_per_zone`, `worker_spot`: folded into the `system_node_pool` and `worker_node_pool` objects.
- Output `metadata_bucket`: now `bucket_name`.
- The node service account's four project roles: the GKE module grants them to the account it creates.
- The node service account's registry access is still scoped to the repository, not project-wide
  (`grant_registry_access` is left off).

## Conservative readings

- **Token creator** is granted on the service account itself, not project-wide; `signBlob` on itself is what Image
  Builder needs.
- **Bucket reader roles**: the procedure says `legacyBucketReader`, the pitfalls section `bucketViewer`; both are granted.
- **Private cluster**: nodes are private; the API endpoint stays public, restrict it with `master_authorized_networks` (required; empty only with `allow_public_api_endpoint = true`).
- **`name` is also used for the service account ID** (`<name>-system`), hence the 23-character limit.
- **`global.UNION_CONTROL_PLANE_HOST`** is not set: the chart 2026.10.1 marks it a deprecated alias of
  `global.CONTROLPLANE_HOST`, which is set.

## Differences from the sibling repo

The sibling repository's `gcp/` folder is pending (a placeholder README, no Terraform), so everything in both roots
here is dataplane-only until it is ported.

### infra

Until the port, every name in this root is here only. Once it lands, only `dataplane.tf`,
`tests/dataplane.tftest.hcl`, `buildkit_node_pool`, `cors_origins`, `fast_registration_retention_days` and the
registry, bucket and service account outputs should remain on this list. Here and not there:

- Files: `dataplane.tf`, `tests/dataplane.tftest.hcl`, `tests/contract.tftest.hcl`, `tests/examples.tftest.hcl`.
- Variables: `allow_public_api_endpoint`, `buildkit_node_pool`, `cors_origins`, `deletion_protection`,
  `fast_registration_retention_days`, `gpu_node_pool`, `kubernetes_version`, `labels`, `master_authorized_networks`,
  `master_ipv4_cidr_block`, `name`, `namespace`, `nodes_cidr`, `pods_cidr`, `project_id`, `region`, `services_cidr`,
  `system_node_pool`, `worker_node_pool`, `zones`.
- Outputs: `artifact_registry_path`, `artifact_registry_repository`, `bucket_name`, `cluster_ca_certificate`,
  `cluster_endpoint`, `cluster_name`, `fast_registration_bucket`, `helm_values`, `kubeconfig_command`, `namespace`,
  `node_service_account_email`, `project_id`, `region`, `service_account_email`.
- Providers and modules: `hashicorp/google`, `hashicorp/google-beta`, `hashicorp/kubernetes`, `hashicorp/random`,
  `module.network`, `module.router`, `module.gke`.

### helm

Until the port, this whole root is here only. Once it lands, only `dataplane.tf`,
`tests/dataplane.tftest.hcl`, the `union_*` variables and `chart_version` should remain on this list. Here and not
there:

- `helm/`.
- Files: `dataplane.tf`, `tests/dataplane.tftest.hcl`, `tests/examples.tftest.hcl`,
  `tests/fixtures/basic.json`, `tests/fixtures/gpu.json`.
- Variables: `infra_state`, `union_client_id`, `union_control_plane_host`, `union_org_name`.
- Outputs: `chart_version`, `namespace`.
- Providers: `hashicorp/helm`, `hashicorp/kubernetes`.

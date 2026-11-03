# Union data plane on Crusoe (self-managed)

Terraform for a self-managed Union.ai data plane on Crusoe Cloud, in two roots applied in order: `infra/` builds
the network, the CMK cluster with its node pools and Cloud Storage with an access key; `helm/` creates the storage
Secret and the Union `dataplane` chart in that cluster. Standalone: nothing here references another cloud folder.

Validated (fmt, validate, tflint, terraform test with mock providers) but not yet applied live.

Base: **provider resources directly** (`crusoecloud/crusoe`). Crusoe has no endorsed upstream Terraform modules for
the network or the cluster.

## What it creates

`infra/` (the Crusoe API):

| File | What |
|---|---|
| `main.tf` | The base: provider, random suffix, labels; VPC network and node subnet (optional NAT gateway); CMK cluster; node pools `system` (3 non-burstable nodes), optional `worker` and `gpu` (tainted `nvidia.com/gpu=true:NoSchedule`). |
| `dataplane.tf` | One Cloud Storage bucket (versioning optional; metadata and fast registration share it, as in the Crusoe values file) and a Cloud Storage access key; the `helm_values` local (the Crusoe layer of the chart values). |

`helm/` (the Kubernetes API):

| File | What |
|---|---|
| `main.tf` | `data.terraform_remote_state.infra` and the `kubernetes` and `helm` providers (kubeconfig at `KUBE_CONFIG_PATH`). |
| `dataplane.tf` | `kubernetes_secret_v1.storage_credentials` (the access key, in namespace `union`) and `helm_release.dataplane` (chart `dataplane` `2026.10.1`: the infra `helm_values` plus the org, host and client ID). |

## Prerequisites

- Terraform 1.11 or newer (validated with 1.16.6) and a Crusoe account with a project.
- `infra/`: authentication through the provider's own configuration, never Terraform variables: the Crusoe CLI config
  (`~/.crusoe/config`) or `CRUSOE_ACCESS_KEY_ID` / `CRUSOE_SECRET_KEY`. The project comes from
  `CRUSOE_DEFAULT_PROJECT` or the CLI config.
- Quota for the chosen VM types in `region`. The provider marks Cloud Storage and subnet NAT gateways "in
  development"; ask Crusoe support to enable them for your organization if needed.
- `helm/`: a kubeconfig from the Crusoe CLI (the `kubeconfig_command` infra output) and a route to the cluster's API
  server. The CMK API endpoint is public (see `allow_public_api_endpoint`), so any host with internet access has one.
- Union side: an org, and `flyte`, `uctl` and `kubectl`.

## Apply

1. Infra (`allow_public_api_endpoint = true` is required, see "Not covered"):
   ```bash
   terraform -chdir=crusoe/infra init && terraform -chdir=crusoe/infra apply -var-file=../../examples/crusoe/infra/basic.tfvars
   ```
   The example's `ssh_public_key` is a placeholder; pass your own with `-var "ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"`.
2. **Create the object-storage access policy** in the Crusoe Cloud Console: the docs require a policy granting the key
   `s3:*` on the bucket and its objects (policy JSON on the Union Crusoe infrastructure page, `<BUCKET_NAME>` = the
   `bucket_name` infra output); without it every request returns `403 Forbidden`. The provider has no policy
   resource.
3. Register the cluster with Union and create the auth Secret:
   ```bash
   eval "$(terraform -chdir=crusoe/infra output -raw kubeconfig_command)"   # writes the kubeconfig entry
   export KUBE_CONFIG_PATH=~/.kube/config KUBECONFIG=~/.kube/config         # where the CLI wrote it
   kubectl cluster-info                                                     # must be this cluster: compare with the cluster_endpoint output
   flyte create config --endpoint <org>.union.ai --org <org>
   flyte create cluster "$(terraform -chdir=crusoe/infra output -raw cluster_name)" --pool default
   uctl selfserve provision-dataplane-resources --clusterName "$(terraform -chdir=crusoe/infra output -raw cluster_name)" --provider custom
   kubectl create namespace union
   kubectl create secret generic union-secret-auth -n union \
     --from-literal=client_secret='<example-client-secret>' --from-literal=app_secret='<example-client-secret>'
   ```
   Both keys hold the same client secret, as the chart writes them when it creates the Secret itself. Save it: Union
   cannot show it again. It never goes through Terraform, so it is in no state.
4. Helm, with the client ID from step 3 and your org in the helm tfvars:
   ```bash
   terraform -chdir=crusoe/helm init && terraform -chdir=crusoe/helm apply -var-file=../../examples/crusoe/helm/basic.tfvars
   ```
   Verify with `kubectl get pods -n union` and `flyte get cluster`.

**The helm providers read only `KUBE_CONFIG_PATH`** (and `KUBE_CTX` to pick a context other than the kubeconfig's
current one). They read neither `KUBECONFIG` nor `~/.kube/config`, and with `KUBE_CONFIG_PATH` unset they fall back to
in-cluster credentials, so a helm apply run inside a pod (a CI runner) would then install into the runner's own
cluster (observed with the pinned `hashicorp/helm`). Set it every time, and check the cluster with `kubectl
cluster-info` first. The kubeconfig is a credential, like the Crusoe CLI config; it is not data passed between the
applies, which is all read from the infra state.

`crusoe_kubeconfig` (a resource and a data source of the provider) is not used for the providers: it would need the
`crusoe` provider in the helm root, and with its default `admin_cert` it writes a cluster-admin key into state.

## State and backends

Neither root commits a `backend` block. With none, both use local state and the helm root reads
`../infra/terraform.tfstate` (the default `infra_state`). For remote state (recommended), add a `backend.tf` to both
roots and give the helm root the infra root's settings once, in its tfvars, as `infra_state = { backend = "<type>",
config = { ... } }`: the same type and settings as the infra backend block. The infra state holds the storage secret
key, and the helm root's runner reads that state in full: give it read-only access, and encrypt both states at rest.
Workspaces other than `default` are not supported.

## Destroy

In reverse: helm first, then infra.

```bash
terraform -chdir=crusoe/helm destroy -var-file=../../examples/crusoe/helm/basic.tfvars
terraform -chdir=crusoe/infra destroy -var-file=../../examples/crusoe/infra/basic.tfvars
```

The helm destroy removes the release and the storage Secret. Delete the `union` namespace (with the auth Secret you
created) by hand if you keep the cluster, and the access policy in the Console. Destroying infra first deletes the
cluster under the helm state, which then only `terraform -chdir=crusoe/helm state rm` clears.

## Inputs

`infra/`:

| Variable | Meaning |
|---|---|
| `region` | Required. A Crusoe location, which is a zone such as `us-east1-a`; the storage region is derived from it. |
| `ssh_public_key` | Required. Public key installed on node-pool VMs (the node pool resource requires one). |
| `allow_public_api_endpoint` | Must be `true`: it acknowledges that the CMK API endpoint is open to any address. |
| `name` | Prefix for every resource (default `union-dataplane`); also the cluster name you register with Union. |
| `labels` | Extra labels merged over `managed-by` and `stack`; applied as bucket tags and node labels. |
| `kubernetes_version` | Default `1.35`; not checked against a live account, confirm it is among the three newest CMK supports. |
| `vpc_cidr`, `subnet_cidr`, `nat_gateway_enabled` | Network. NAT is off by default (in development at Crusoe); enable it if nodes have no public IP. |
| `system_node_pool`, `worker_node_pool`, `gpu_node_pool` | One object per pool; the last two carry `enabled`. `c1a.8x` (8 vCPU / 32 GB) is the system default because the data plane requests 14 vCPU / 27 GiB across the system pool. Instance type names come from Crusoe's docs, not Union's. |
| `bucket_versioning_enabled` | Off by default; cannot be disabled once enabled. |

`helm/`:

| Variable | Meaning |
|---|---|
| `union_client_id` (required) | Client ID from `uctl selfserve provision-dataplane-resources` (`global.AUTH_CLIENT_ID`) |
| `union_control_plane_host` (required) | Control plane hostname, no scheme or port (`global.CONTROLPLANE_HOST`), for example `<org>.union.ai` |
| `union_org_name` (required) | Union organization name (`global.ORG_NAME`) |
| `infra_state` | Where the infra state is (section "State and backends"); default the local `../infra/terraform.tfstate` |

## Outputs

`infra/`: `bucket_name`, `cluster_endpoint`, `cluster_id`, `cluster_name`, `helm_values` (the Crusoe layer of the
chart values, with the GPU toleration; no credentials and no org, host or client ID), `kubeconfig_command`, `location` (the zone you passed as
`region`), `region` (the region derived from it, for `storage.region`), `storage_access_key_id`, `storage_endpoint`,
`storage_secret_access_key` (sensitive). The helm root reads `helm_values`, `storage_access_key_id` and
`storage_secret_access_key` (its providers use the kubeconfig at `KUBE_CONFIG_PATH`); the rest are for you.

`helm/`: `namespace`, the release's namespace (`union`).

## Add-ons

None. The Tailscale and MCP add-ons (CONVENTIONS.md section 4) do not apply to the dataplane, which serves no
endpoint of its own.

## Not covered, and why

- **Object-storage access policy (manual, Apply step 2).** The provider has no policy resource.
- **The `dataplane-crds` chart.** The deploy page installs it, but at `2026.10.1` it is deprecated, and with its
  defaults it renders only the FlyteWorkflow CRD, which the `dataplane` chart installs itself from its `crds/`.
- **The NVIDIA device plugin.** Not installed here, as before the split; whether CMK GPU nodes ship it is not
  verified. If `kubectl describe node` on a GPU node shows no `nvidia.com/gpu` capacity, install it.
- **A check that the auth Secret exists.** The chart does not check for `union-secret-auth`; without it the helm
  apply waits out its 15-minute timeout with crashlooping pods. Reading the Secret from Terraform would copy it into
  state, so Apply step 3 is the only guard.
- **Container registry.** The Crusoe pages do not ask for one (use `--image` or the remote builder).
- **CORS and lifecycle rules on the bucket.** Not on the Crusoe pages, and the provider has no resource for them.
- **Workload identity.** Crusoe uses static access keys per the docs (`authType: accesskey`).
- **Separate fast-registration bucket.** The Crusoe values file uses one bucket for both; so does this.
- **Autoscaling, spot pools.** CMK node pools here have a fixed `node_count`; the docs list no Crusoe-specific
  autoscaling settings. The shared "optional pools scale from zero" default therefore does not hold on Crusoe.
- **`cluster_ca_certificate` output.** The cluster resource does not expose it; the kubeconfig carries it.
- **`PathStyleRequestNotAllowed` fix.** A Helm values change (`provider: custom` with a `stow` block), not made here.
- **Provider project as a variable.** The original exposed `project`; the provider's environment variable and CLI
  config cover it, and credentials-adjacent settings stay out of Terraform inputs.
- **Bucket name as a variable.** The bucket is now `<name>-<suffix>`, so two copies can run side by side.
- **Restricting the Kubernetes API.** The CMK API endpoint is public and open to any address (Kubernetes
  authentication still applies), so the infra plan fails unless `allow_public_api_endpoint = true` acknowledges it
  (CONVENTIONS.md section 2). The provider has no CIDR list for it, and its only control, the cluster's `private`
  ("without a public IP"), is left unset because the docs do not say whether it also takes public addresses from the
  nodes, which need egress to the Union control plane while NAT is off by default.

## Not verified

These were not run against a live account:

- Where `crusoe kubernetes clusters get-credentials` writes the kubeconfig (assumed `~/.kube/config`; check its
  output) and that both providers work with it through `KUBE_CONFIG_PATH`. That the providers honour
  `KUBE_CONFIG_PATH` and `KUBE_CTX` with empty provider blocks was checked against an unreachable server.
- `storage_endpoint` is the bucket's `s3_url`; the docs only say `<YOUR_STORAGE_ENDPOINT>`. Verify it is the regional
  S3 endpoint.

## Conservative readings

- Pod CIDR, service CIDR and routing mode stay at CMK defaults; the docs give no Crusoe sizing.
- Bucket versioning is off because it cannot be disabled later and the Crusoe pages do not ask for it.
- The storage secret key lives in the infra state (the API returns it once) and, through the Secret, in the helm
  state; use encrypted remote backends.
- `union_control_plane_host` has no default (the original defaulted it to `<org>.union.ai`), so the host the dataplane
  connects to is always stated.

## Changed from union-dataplane-tf

The variable `location` of the original is `region` here (shared convention) and still holds a Crusoe location, i.e.
a zone such as `us-east1-a`. Outputs follow the original: `location` returns that zone and `region` the region derived
from it (no zone letter); the `storage_region` output was dropped because it duplicated `region`. The GPU pool is
tainted `nvidia.com/gpu=true:NoSchedule`. Crusoe documents no `ExtendedResourceToleration` admission plugin, so the
infra `helm_values` add the matching toleration to task pods that request `nvidia.com/gpu` through Flyte's
`config.k8s.plugins.k8s.resource-tolerations`; CPU task pods get none and stay off the GPU nodes. The Helm install and
the storage Secret, manual steps in the original, are the `helm/` root.

Variables renamed or folded: `cluster_name` is now `name`. `system_instance_type` and `system_node_count` became
`system_node_pool.instance_type` and `system_node_pool.node_count` (at least 3, which the original only recommended).
`worker_instance_type` and `worker_node_count` became `worker_node_pool.instance_type` and
`worker_node_pool.node_count`; the original created the worker pool when `worker_instance_type` was non-null, now
`worker_node_pool.enabled` (default `false`) does. `bucket_name` is no longer set: the bucket is `name` plus a random
suffix (so the globally unique name needs no picking) and the `bucket_name` output returns it. `storage_key_alias`
(default `union-dataplane`) is dropped as a setting: the access key alias is `name`, so that the keys of two deployments
in one project can be told apart without a second variable. `project` (the provider's project) is no longer a variable:
the provider's environment variable and CLI config cover it.

## Differences from the sibling repo

The sibling repository (`terraform-flyte`) has no folder for this cloud: Crusoe is Union-only, so every file,
variable and output of both roots is specific to this repository.

### infra

Here and not there:

- Every file, variable and output of `infra/`, as above. `dataplane.tf` is the product file (`flyte.tf` in the
  sibling). If the sibling gains a Crusoe folder, only `dataplane.tf`, `tests/dataplane.tftest.hcl`,
  `bucket_versioning_enabled`, `storage_*`, `location` and `helm_values` should remain here.

### helm

Here and not there:

- `helm/`, the whole root: the Union dataplane chart and its storage Secret. There is no `tailscale.tf` or `mcp.tf`.

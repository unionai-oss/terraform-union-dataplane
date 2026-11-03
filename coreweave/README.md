# Union dataplane on CoreWeave (CKS)

Terraform for a self-managed Union.ai dataplane on CoreWeave Kubernetes Service, in two roots applied in order:
`infra/` builds the VPC, the CKS cluster and AI Object Storage with its access policy and key; `helm/` creates the
system node pool, the storage Secret and the Union `dataplane` chart in that cluster. Union runs the control plane.

Validated (fmt, validate, tflint, terraform test with mock providers) but not yet applied live.

**Provider resources directly** ([`coreweave/coreweave`](https://registry.terraform.io/providers/coreweave/coreweave)):
there is no endorsed upstream module for CoreWeave in [CONVENTIONS.md](../CONVENTIONS.md).

## What it creates

`infra/` (the CoreWeave API):

| File | Resources |
|---|---|
| `main.tf` | `coreweave_networking_vpc` (pod, service and internal-LB prefixes; defaults are a /13 pod CIDR, /22 service and LB ranges, /18 host prefix), `coreweave_cks_cluster`, the random name suffix |
| `dataplane.tf` | `coreweave_object_storage_organization_access_policy` (`s3:*` on the bucket(s); also a provider prerequisite for creating any bucket), the metadata bucket with versioning, an optional second fast-registration bucket with an expiry rule (default 7 days), `coreweave_object_storage_access_key`, the `helm_values` local (the CoreWeave layer of the chart values) |

`helm/` (the Kubernetes API):

| File | Resources |
|---|---|
| `main.tf` | `data.terraform_remote_state.infra` and the `kubernetes` and `helm` providers (kubeconfig at `KUBE_CONFIG_PATH`) |
| `dataplane.tf` | `kubernetes_manifest.system_node_pool` (the CKS `NodePool` in [`helm/files/system-nodepool.yaml`](helm/files/system-nodepool.yaml), waited on until `AtTarget`), `kubernetes_secret_v1.storage_credentials` (the access key, in namespace `union`), `helm_release.dataplane` (chart `dataplane` `2026.10.1`: the infra `helm_values` plus the org, host and client ID) |

Bucket and policy names are `<name>-<random suffix>...`, so two copies can run side by side. `labels` are applied as
bucket tags (the VPC and cluster resources have no label argument).

The system node pool is in `helm/` because CKS node pools are `NodePool` custom resources created through the
Kubernetes API; the provider has no node-pool resource. So on CoreWeave a returned infra apply means the cluster
exists, and the nodes arrive during the helm apply, which waits for them before installing the chart.

## Prerequisites

- Terraform `>= 1.11.0, < 2.0.0`.
- `infra/`: a CoreWeave API token in `COREWEAVE_API_TOKEN` (`CW-SECRET-...`); the same token is used for Object
  Storage calls. It is never a Terraform variable.
- `helm/`: the cluster's kubeconfig, downloaded from the CoreWeave Cloud Console (Kubernetes > Clusters) after the
  infra apply, and **a route to the cluster's API server**. With the default `allow_public_api_endpoint = false` the
  API server has no public ingress, so run the helm apply (and `kubectl`) from a host with a route into the cluster's
  VPC, or set `allow_public_api_endpoint = true` in the infra root. The infra apply needs no such route: nothing in
  `infra/` talks to the Kubernetes API.
- Quota for 3 nodes of the system pool's instance type in your zone (`cd-gp-i64-erapids`, 64 vCPU / 512 GB,
  non-burstable; check the [CPU instances page](https://docs.coreweave.com/platform/instances/cpu-instances) and change
  `instanceType` in `helm/files/system-nodepool.yaml` if your zone lacks it).
- A Union.ai organization, and `flyte`, `uctl` and `kubectl`.

## Apply

1. Infra:
   ```bash
   export COREWEAVE_API_TOKEN=<example-coreweave-api-token>
   terraform -chdir=coreweave/infra init && terraform -chdir=coreweave/infra apply -var-file=../../examples/coreweave/infra/minimal.tfvars
   ```
2. Register the cluster with Union and create the auth Secret. `cluster_name` is an infra output.
   ```bash
   export KUBE_CONFIG_PATH=$PWD/coreweave-kubeconfig   # downloaded from the Cloud Console
   export KUBECONFIG=$KUBE_CONFIG_PATH
   kubectl cluster-info                               # must be this cluster: compare with the cluster_endpoint output
   flyte create config --endpoint <org>.union.ai --org <org>
   flyte create cluster "$(terraform -chdir=coreweave/infra output -raw cluster_name)" --pool default
   uctl selfserve provision-dataplane-resources --clusterName "$(terraform -chdir=coreweave/infra output -raw cluster_name)" --provider custom
   kubectl create namespace union
   kubectl create secret generic union-secret-auth -n union \
     --from-literal=client_secret='<example-client-secret>' --from-literal=app_secret='<example-client-secret>'
   ```
   Both keys hold the same client secret, as the chart writes them when it creates the Secret itself. Save it: Union
   cannot show it again. It never goes through Terraform, so it is in no state.
3. Helm, with the client ID from step 2 and your org in the helm tfvars:
   ```bash
   terraform -chdir=coreweave/helm init && terraform -chdir=coreweave/helm apply -var-file=../../examples/coreweave/helm/minimal.tfvars
   ```
   Verify with `kubectl get pods -n union` and `flyte get cluster`.

**The helm providers read only `KUBE_CONFIG_PATH`** (and `KUBE_CTX` to pick a context other than the kubeconfig's
current one). They read neither `KUBECONFIG` nor `~/.kube/config`, and with `KUBE_CONFIG_PATH` unset they fall back to
in-cluster credentials, so a helm apply run inside a pod (a CI runner) would then install into the runner's own
cluster (observed with the pinned `hashicorp/helm`). Set it every time, and check the cluster with `kubectl
cluster-info` first. The kubeconfig is a credential, like `COREWEAVE_API_TOKEN`; it is not data passed between the
applies, which is all read from the infra state.

The helm example's values are placeholders; the client ID is not a secret, but keep your real tfvars out of a public
repository.

## State and backends

Neither root commits a `backend` block. With none, both use local state and the helm root reads
`../infra/terraform.tfstate` (the default `infra_state`). For remote state (recommended), add a `backend.tf` to both
roots and give the helm root the infra root's settings once, in its tfvars, for example with CoreWeave AI Object
Storage's S3 API:

```hcl
infra_state = { backend = "s3", config = { bucket = "example-tfstate", key = "union-dataplane/coreweave/infra.tfstate", region = "US-EAST-04A", endpoints = { s3 = "https://cwobject.com" }, use_lockfile = true, skip_credentials_validation = true, skip_region_validation = true, skip_requesting_account_id = true } }
```

The `s3` backend settings for CoreWeave above are not verified against a live account. The infra state holds the
object storage secret key, and the helm root's runner reads that state in full: give it read-only access, and encrypt
both states at rest. Workspaces other than `default` are not supported.

## Destroy

In reverse: helm first, then infra.

```bash
terraform -chdir=coreweave/helm destroy -var-file=../../examples/coreweave/helm/minimal.tfvars
terraform -chdir=coreweave/infra destroy -var-file=../../examples/coreweave/infra/minimal.tfvars
```

The helm destroy removes the release, the Secret and then the system node pool. Delete the `union` namespace (with
the auth Secret you created) by hand if you keep the cluster. Destroying infra first deletes the cluster under the
helm state, which then only `terraform -chdir=coreweave/helm state rm` clears.

## Inputs

`infra/`:

| Variable | Meaning |
|---|---|
| `region` (required) | CoreWeave Availability Zone (for example `US-EAST-04A`). CoreWeave calls it a zone; it is named `region` for the shared convention and doubles as the S3 region in the Helm values |
| `name` | VPC and cluster name, also the Union cluster name (default `union-dataplane`; at most 30 characters, not starting with `cw-` or `vip-`) |
| `labels` | Extra labels merged over `managed-by` and `stack` |
| `kubernetes_version` | CKS minor version (default `v1.35`) |
| `allow_public_api_endpoint` | Default `false`: the API server has no public ingress. `true` makes it reachable from any address (authentication still applies); the public ingress takes no CIDR list |
| `host_prefix`, `pod_cidr`, `service_cidr`, `internal_lb_cidr` | VPC prefixes |
| `separate_fast_registration_bucket`, `fast_registration_retention_days` | Second bucket with an expiry rule (default `false`: one bucket, no expiry) |
| `access_key_duration_seconds` | Access key lifetime; default `0`, permanent |

`helm/`:

| Variable | Meaning |
|---|---|
| `union_client_id` (required) | Client ID from `uctl selfserve provision-dataplane-resources` (`global.AUTH_CLIENT_ID`) |
| `union_control_plane_host` (required) | Control plane hostname, no scheme or port (`global.CONTROLPLANE_HOST`), for example `<org>.union.ai` |
| `union_org_name` (required) | Union organization name (`global.ORG_NAME`) |
| `infra_state` | Where the infra state is (section "State and backends"); default the local `../infra/terraform.tfstate` |

## Outputs

`infra/`: `access_key_id`, `bucket_name`, `cluster_endpoint`, `cluster_id`, `cluster_name`,
`fast_registration_bucket_name`, `helm_values` (the CoreWeave layer of the chart values, no credentials and no org,
host or client ID), `object_storage_endpoint`, `region`, `secret_key` (sensitive). The helm root reads `helm_values`,
`access_key_id` and `secret_key` (its providers use the kubeconfig at `KUBE_CONFIG_PATH`); `cluster_name` is also the name to register with `flyte create cluster`.

`helm/`: `namespace`, the release's namespace (`union`).

## Add-ons

None. The Tailscale and MCP add-ons (CONVENTIONS.md section 4) do not apply to the dataplane, which serves no
endpoint of its own.

## Not covered, and why

- **Worker or GPU node pools.** Only the system pool is created. For another pool, copy
  `helm/files/system-nodepool.yaml`, change `name`, `targetNodes` (or `minNodes`/`maxNodes` with `autoscaling: true`)
  and, for GPU, a GPU `instanceType`, and `kubectl apply` it; Union injects the tolerations and selectors for GPU task
  pods.
- **`kubeconfig_command` and `cluster_ca_certificate` outputs.** The provider issues no kubeconfig or CA, and there is
  no CLI command for one; download the kubeconfig from the Cloud Console.
- **The `dataplane-crds` chart.** The deploy page installs it, but at `2026.10.1` it is deprecated, and with its
  defaults it renders only the FlyteWorkflow CRD, which the `dataplane` chart installs itself from its `crds/`.
- **A check that the auth Secret exists.** The chart does not check for `union-secret-auth`; without it the helm
  apply waits out its 15-minute timeout with crashlooping pods. Reading the Secret from Terraform would copy it into
  state, so step 2 is the only guard.
- **CORS (GET/HEAD from `https://*.unionai.cloud`, Code Viewer).** The CoreWeave page gives no CORS configuration and
  the provider has no CORS resource. Apply it with the S3 API if you use the Code Viewer.
- **Container registry for the image builder.** The CoreWeave pages do not provision one. The provider offers
  `coreweave_container_registry_namespace`, but adding it would invent a requirement.
- **Workload identity / IAM roles.** CoreWeave authenticates with the S3 access key in the `storage-credentials`
  Secret; there is no cloud role to create.
- **Explicit NAT / egress.** CKS VPCs allow public egress by default, which covers the control-plane egress (443, and
  7844 for the tunnel). Do not set `disable_public_access`.
- **Task-pod endpoint override.** The troubleshooting table says to add `FLYTE_AWS_ENDPOINT=https://<BUCKET>.cwobject.com`
  to `config.k8s.plugins.k8s.default-env-vars` only if task pods hit `s3.us-east-1.amazonaws.com`; it is not in the
  base values, so it is not in `helm_values`.
- **The provider's per-CIDR `kube_api_access` and its `tailscale` cluster setting.** Either could give the helm apply a
  route to a private API server, but CoreWeave support has to enable `kube_api_access` per organization, and neither
  was tried, so neither is wired.

## Not verified

These were not run against a live account:

- The kubeconfig from the Cloud Console working with both providers through `KUBE_CONFIG_PATH`. That the providers
  honour `KUBE_CONFIG_PATH` and `KUBE_CTX` with empty provider blocks was checked against an unreachable server.
- The `AtTarget` condition the helm root waits on, taken from CoreWeave's NodePool documentation.
- The S3 backend settings for AI Object Storage under "State and backends".

## Conservative readings

- One bucket by default, as the deploy page sets both bucket values to the same name. With
  `separate_fast_registration_bucket = true` a second bucket gets the expiry rule; the metadata bucket never does.
  Clusters in different pools need different metadata buckets.
- The access policy uses `principals = ["*"]` exactly as the doc's JSON does. Policy resources are bucket names rather
  than references so the policy is created before the buckets (CoreWeave requires a policy first).
- `access_key_duration_seconds = 0` (permanent) because the docs state no expiry; rotate with
  `terraform -chdir=coreweave/infra apply -replace=coreweave_object_storage_access_key.this`, then apply helm again to
  update the Secret.
- `kubernetes_version` defaults to `v1.35`, the version in the provider docs; check it is among the three most recent
  minors CKS offers when you apply.
- `name` is used for both the CKS cluster and the Union cluster name (the deploy page asks for one name); it is
  limited to 30 characters by CKS.
- `allow_public_api_endpoint = false` by default, so the Kubernetes API is never open to any address unless asked for
  (CONVENTIONS.md section 2).
- The S3 `region` in the Helm values is the Availability Zone, as the deploy page shows.
- `union_control_plane_host` has no default (the original defaulted it to `<org>.union.ai`), so the host the dataplane
  connects to is always stated.

## Changed from union-dataplane-tf

Outputs renamed relative to the original `union-dataplane-tf/coreweave`: `api_server_endpoint` is now
`cluster_endpoint` and `zone` is now `region` (the variable is `region`, holding the Availability Zone). The access
key's `attributes` are the fixed map `{ application = "union-dataplane" }` as in the original; they are not derived
from `labels`, because changing them replaces the key. `cluster_public` (default `true`) is now
`allow_public_api_endpoint` (default `false`), so the API server is private unless you opt in. The Helm install, the
storage Secret and the system node pool, manual steps in the original, are the `helm/` root.

Variables renamed or derived: `cluster_name` is now `name` (the cluster and the VPC carry it). `zone` is now `region`.
`bucket_name` is no longer set: the metadata bucket is `local.unique_name`, which is `name` plus a random suffix, so
that the globally unique bucket name does not need picking (the outputs `bucket_name` and
`fast_registration_bucket_name` return it). `fast_registration_bucket_name` is replaced by the bool
`separate_fast_registration_bucket`: false (default) keeps both in the one bucket, as the original did when it was null;
true creates a second bucket named `<unique_name>-fast-reg` with the retention rule. `access_policy_name` is dropped as
a setting: the organization access policy is named `local.unique_name`, like the bucket, so that it is unique per
deployment. `cluster_public` is `allow_public_api_endpoint`, as above.

## Differences from the sibling repo

The sibling repository, [terraform-flyte](https://github.com/unionai-oss/terraform-flyte), has no folder for this
cloud: CoreWeave is Union-only, so every file, variable and output of both roots is specific to this repository.

### infra

Here and not there:

- Every file, variable and output of `infra/`, as above. `dataplane.tf` is the product file (`flyte.tf` in the
  sibling); there is no `exposure.tf` or `oauth.tf`, because the dataplane serves no endpoint of its own.
  `tests/storage.tftest.hcl` holds the original's bucket and expiry assertions.

### helm

Here and not there:

- `helm/`, the whole root: the Union dataplane chart, its storage Secret and the system node pool, with
  `files/system-nodepool.yaml`. There is no `tailscale.tf` or `mcp.tf`.

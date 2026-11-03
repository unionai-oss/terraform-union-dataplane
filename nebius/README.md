# Union data plane on Nebius (self-managed)

Terraform for a self-managed Union.ai data plane on Nebius, in two roots applied in order: `infra/` builds a Managed
Kubernetes (MK8s) cluster, Object Storage, a service account with an access key, and a Container Registry; `helm/`
installs the Union `dataplane` chart on that cluster, reading everything it needs from the infra root's state.
Standalone: nothing here references another cloud folder.

Validated (fmt, validate, tflint, terraform test with mock providers) but not yet applied live.

## What it creates

`infra/`:

| File | What |
|---|---|
| `terraform.tf` | Terraform and provider pins. |
| `main.tf` | The base: provider, random suffix, labels; MK8s cluster; node groups `system` (3 fixed non-burstable nodes), optional autoscaled `worker` and `gpu`. |
| `dataplane.tf` | Metadata bucket (versioned) and fast-registration bucket (expiry lifecycle rule), both with the Code Viewer CORS rule and a bucket policy giving `storage.editor` to a dedicated IAM group; service account in that group with an Object Storage access key; Container Registry; the Helm values. |
| `variables.tf`, `outputs.tf` | Inputs and outputs, including the `helm_values` YAML string. |

`helm/`:

| File | What |
|---|---|
| `main.tf` | The infra root's state (`data.terraform_remote_state.infra`); the `kubernetes` and `helm` providers, authenticated by the Nebius CLI. |
| `dataplane.tf` | The Secret `storage-credentials` from the infra access key; the Union `dataplane` chart 2026.10.1 in namespace `union`. |

Base: **provider resources directly** (`nebius/nebius`). Nebius has no endorsed upstream Terraform modules for the
cluster. The network is an existing subnet you pass in (see below).

## Prerequisites

- Terraform 1.11 or newer (validated with 1.16.6).
- Authentication through the provider's own configuration, never Terraform variables: the Nebius CLI profile
  (`nebius profile create`) or `NEBIUS_IAM_TOKEN`.
- The Nebius CLI (`nebius`) on `PATH` for the helm apply: the `kubernetes` and `helm` providers run
  `nebius mk8s v1 cluster get-token --format json` with the CLI's default profile. That is the exec entry a
  kubeconfig from `nebius mk8s cluster get-credentials --external` contains, as reported from such a kubeconfig;
  it was not run here (no Nebius account). If your CLI writes a different one, copy its `command` and `args`.
- For the helm apply, a route to the public API endpoint: run it from inside `public_endpoint_allowed_cidrs`.
- A Nebius tenant and project (`tenant_id`, `parent_id`), quota for the node platforms you pick (and GPU quota if
  used), permission to create IAM groups at tenant level.
- An existing VPC subnet in the project (`nebius vpc subnet list`; every project has a default one).
- Union side: an org, and the `flyte`, `uctl` and `kubectl` tools from the deploy page.

## Apply

`region` has no default and must match the project's region. Set your own values in copies of the examples
([`../examples/nebius/`](../examples/nebius/)).

1. The infra root:
   ```bash
   terraform -chdir=nebius/infra init && terraform -chdir=nebius/infra apply -var-file=../../examples/nebius/infra/basic.tfvars
   ```
2. Register the cluster with Union and create the auth Secret the chart reads. It is not in Terraform, because it
   holds the client secret:
   ```bash
   $(terraform -chdir=nebius/infra output -raw kubeconfig_command)
   flyte create config --endpoint <org>.union.ai --org <org>
   flyte create cluster "$(terraform -chdir=nebius/infra output -raw cluster_name)" --pool default
   uctl selfserve provision-dataplane-resources --clusterName "$(terraform -chdir=nebius/infra output -raw cluster_name)" --provider custom
   kubectl create namespace union
   kubectl create secret generic union-secret-auth -n union \
     --from-literal=client_secret=<client secret from uctl> --from-literal=app_secret=<client secret from uctl>
   ```
3. The helm root, with the client ID from step 2 and your org in its tfvars:
   ```bash
   terraform -chdir=nebius/helm init && terraform -chdir=nebius/helm apply -var-file=../../examples/nebius/helm/basic.tfvars
   ```

The chart does not check that `union-secret-auth` exists: without it the release waits out its 15-minute timeout
with crashlooping pods. The helm root creates `storage-credentials` (the Object Storage key) before the chart,
which reads it when it renders.

Registry: create a long-lived token and the `flyte create secret --type image_pull ...` secret as on the deploy page;
use `registry_url` as the `flyte.Image` registry.

## State and backends

Neither root has a `backend` block: where state lives is your choice.

1. **First run, nothing configured:** both roots use local state, and `helm/` reads `../infra/terraform.tfstate`
   (`infra_state` defaults to that).
2. **Remote state (recommended):** add a `backend.tf` to both roots, then tell `helm/` where the infra state is,
   once, in its tfvars, with the same settings as the infra backend block. For a bucket on Nebius Object Storage:
   ```hcl
   infra_state = { backend = "s3", config = { bucket = "example-tfstate", key = "union-dataplane/nebius/infra.tfstate", region = "eu-north1", endpoints = { s3 = "https://storage.eu-north1.nebius.cloud" }, skip_region_validation = true, skip_credentials_validation = true, skip_requesting_account_id = true, skip_s3_checksum = true } }
   ```
3. Both states are secrets: `infra/` holds the Object Storage secret key, and `helm/` holds it again in the
   `storage-credentials` Secret. Use backends with encryption at rest and restricted access, and give the helm
   runner read-only access to the infra state.

Terraform workspaces are not supported: `helm/` reads the infra root's default workspace.

## Destroy, in reverse

```bash
terraform -chdir=nebius/helm  destroy -var-file=../../examples/nebius/helm/basic.tfvars
terraform -chdir=nebius/infra destroy -var-file=../../examples/nebius/infra/basic.tfvars
```

`helm/` first: it removes the chart, whose Services own Nebius load balancers. Destroying `infra/` first orphans
them; recovering takes `terraform -chdir=nebius/helm state rm` of everything, and deleting the load balancers by
hand. The Secret you created in step 2 goes with the cluster.

## Inputs

`infra/`:

| Variable | Meaning |
|---|---|
| `region`, `parent_id`, `tenant_id`, `subnet_id` | Required. `region` only builds the Object Storage endpoint and registry URL. |
| `name` | Prefix for every resource (default `union-dataplane`); also the cluster name you register with Union. |
| `labels` | Extra labels merged over `managed-by` and `stack`; applied to every resource that has labels. |
| `kubernetes_version` | Default `1.34`; not checked against a live tenant, confirm it is among the three newest Nebius offers. |
| `public_endpoint_allowed_cidrs`, `allow_public_api_endpoint` | CIDRs allowed to reach the public Kubernetes API endpoint. Required: an empty list (which Nebius reads as unrestricted) is rejected unless `allow_public_api_endpoint = true`, so the API is never open to any address by default. |
| `node_public_ip` | Default `true`: the provider has no NAT gateway resource, so a public address is the egress path to Union. |
| `system_node_pool`, `worker_node_pool`, `gpu_node_pool` | One object per pool; the last two carry `enabled` and scale from zero. Platform and preset names (`cpu-d3` / `4vcpu-16gb`, `gpu-h200-sxm` / `8gpu-128vcpu-1600gb`) are not verified in your region. |
| `fast_registration_retention_days` | Default 7. |

`helm/`:

| Variable | Meaning |
|---|---|
| `union_client_id` (required) | The client ID `uctl selfserve provision-dataplane-resources` printed (`global.AUTH_CLIENT_ID`); its secret is in `union-secret-auth`. |
| `union_org_name` (required) | Union organization name (`global.ORG_NAME`). |
| `union_control_plane_host` | Control plane host, no scheme or port (`global.CONTROLPLANE_HOST`). Default `null`: `<union_org_name>.union.ai`, as on the Nebius deploy page. |
| `infra_state` | Where the infra state is (default: `../infra/terraform.tfstate`); see "State and backends". |

## Outputs

`infra/`: `access_key_id`, `bucket_name` (metadata), `cluster_ca_certificate`, `cluster_endpoint`, `cluster_id`,
`cluster_name`, `fast_registration_bucket`, `helm_values` (the Nebius layer of the chart values), `kubeconfig_command`,
`region`, `registry_id`, `registry_url`, `secret_access_key` (sensitive), `service_account_id`, `storage_endpoint`.
The helm root reads `cluster_endpoint`, `cluster_ca_certificate`, `helm_values`, `access_key_id` and
`secret_access_key` from state; the rest are for you. Clusters in one pool share a metadata bucket; clusters in different pools need
different ones.

`helm/`: `namespace`, the release namespace.

## GPU

The GPU pool is tainted `nvidia.com/gpu=true:NoSchedule`. Nebius documents no `ExtendedResourceToleration`
admission plugin, so `helm_values` gives task pods that request `nvidia.com/gpu` the matching toleration
(`config.k8s.plugins.k8s.resource-tolerations`); CPU task pods stay off the GPU nodes. The pool requests the NVIDIA
drivers preset `gpu_node_pool.drivers_preset` (default `cuda12`; check `nebius mk8s node-group
get-compatibility-matrix` for your platform, or set it to `""` and install the GPU operator yourself). Add the
`config.k8s.plugins.k8s` GPU label block from the deploy page once you know your node labels.

## Add-ons

None: the optional pieces are the worker and GPU pools, infra inputs.

## Not covered, and why

- **VPC and subnet.** The Nebius pages ask for nothing beyond a subnet, and the original takes an existing one. The
  provider does have `nebius_vpc_v1_network` and `nebius_vpc_v1_subnet`, but they need address-pool settings that
  cannot be checked without an account, so the project's default subnet is used. NAT: no provider resource.
- **Registry pull token.** Issued through the Nebius CLI or console; no Terraform resource. Manual.
- **`uctl`, `flyte create cluster`, the OAuth client secret.** Union-side steps, and the secret is a credential
  Union issues: you create `union-secret-auth` (Apply, step 2), so it never reaches Terraform state.
- **Image pull secret for Union system images, persistent logging.** Not on the Nebius pages.
- **`metadata_bucket` output.** Renamed `bucket_name`, the shared output name.
- **Fixed bucket names.** Buckets are suffixed with a random id, so two copies can run side by side.

## Conservative readings

- CORS is not on the Nebius page; it is applied because the general infrastructure page says the per-cloud buckets
  need it for the Code Viewer. The metadata bucket gets it too since a single bucket may serve as fast-registration.
- The docs mention a "service account + access key" without roles; `storage.editor` on the two buckets (via a
  dedicated group, since Nebius bucket policies bind roles to groups) is the narrowest read.
- The access key secret is stored in both states (sensitive); use encrypted remote backends.
- Whether Nebius accepts `min_nodes = 0` on an autoscaled node group was not checked; raise it if the API rejects it.
- The chart has no Nebius overlay, so `helm_values` is the whole cloud layer of the release's values.

## Validation

`terraform fmt -check`, `terraform init -backend=false -lockfile=readonly`, `terraform validate`, `tflint` (the
`terraform` ruleset; Nebius has none) and `terraform test` with mock providers pass for both roots. `terraform plan`
against a real project and `apply` were not run: there are no credentials.

## Changed from union-dataplane-tf

Variables renamed: `cluster_name` is now `name`. `org_name` is now `union_org_name` (shared convention; it is in the
`helm/` root, where the org is used). `system_node_group` is now `system_node_pool`, with the field `nodes` renamed
`node_count`. `worker_node_group` is now `worker_node_pool`: the original created it when the variable was non-null, now
`worker_node_pool.enabled` (default `false`) does, and its fields `platform`, `preset`, `min_nodes` and `max_nodes` keep
their names. GPUs have their own `gpu_node_pool` instead of a GPU platform in the worker pool. The Helm install, a
manual step in the original, is the `helm/` root.

## Differences from the sibling repo

The sibling repository (`terraform-flyte`) has no folder for this cloud: Nebius is Union-only. So every file,
variable, output and provider of both roots is specific to this repository, and there is nothing of the same name
to differ in meaning. If the sibling gains a Nebius folder, only `infra/dataplane.tf`, `helm/dataplane.tf`, their
tests, `fast_registration_retention_days`, the `union_*` variables and the storage, registry and service account
outputs should remain here.

### infra

Here and not there:

- Everything: `main.tf`, `dataplane.tf` (the product file; `flyte.tf` in the sibling's clouds) and the rest of the
  root, with the dataplane-only variable `fast_registration_retention_days` and the outputs that feed the helm root
  and the Union registration (`access_key_id`, `fast_registration_bucket`, `helm_values`, `registry_id`,
  `registry_url`, `secret_access_key`, `service_account_id`, `storage_endpoint`).

Same name, different meaning or default:

- None: the sibling has no Nebius root.

### helm

Here and not there:

- `helm/`: the whole root, which installs the Union `dataplane` chart (`dataplane.tf`) with the variables
  `union_client_id`, `union_control_plane_host` and `union_org_name`.

Same name, different meaning or default:

- None: the sibling has no Nebius root.

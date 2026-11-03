# Union dataplane on OCI (OKE)

Terraform for a self-managed Union.ai dataplane on Oracle Cloud, in two roots applied in order: `infra/` builds the
VCN, the OKE cluster, Object Storage buckets, an OCIR repository and instance-principal access; `helm/` installs the
Union `dataplane` chart on that cluster, reading everything it needs from the infra root's state. Union runs the
control plane.

Validated (fmt, validate, tflint, terraform test with mock providers) but not yet applied live.

Base: **provider resources directly** (`oracle/oci`): there is no endorsed upstream module for OCI in
[CONVENTIONS.md](../CONVENTIONS.md).

## What it creates

`infra/`:

| File | Resources |
|---|---|
| `main.tf` | VCN (10.0.0.0/16), private /18 subnet (nodes and pods), public /24 subnet (API endpoint, load balancers), internet and NAT gateways, route tables, security lists; OKE cluster (VCN-native pod networking, public API endpoint); the cluster's kubeconfig (read for its CA); system node pool (3 nodes, 4 OCPU / 32 GB, spread over all availability domains); optional worker pool (optionally preemptible); the random name suffix |
| `dataplane.tf` | Metadata bucket (versioning on); fast-registration bucket with a delete-after-N-days lifecycle rule (default 7) and the service policy OCI requires for lifecycle rules; private OCIR repository `<name>-<suffix>/imagebuilder`; dynamic group and policy for instance principals (Option A); optional S3-compatibility customer secret key (Option B); the `helm_values` local |

`helm/`:

| File | Resources |
|---|---|
| `main.tf` | The infra root's state (`data.terraform_remote_state.infra`); the `kubernetes` and `helm` providers, authenticated by `oci ce cluster generate-token` |
| `dataplane.tf` | The Secret `storage-credentials` from the Option B key (only when infra created one); the Union `dataplane` chart 2026.10.1 in namespace `union` |

Every tenancy-unique name (buckets, repository, dynamic group, policies) is `<name>-<random suffix>...`, so two
copies can run side by side. Every taggable resource carries `labels` as freeform tags.

## Prerequisites

- Terraform `>= 1.11.0, < 2.0.0`.
- OCI credentials from the environment (`OCI_CLI_*`, or `TF_VAR_tenancy_ocid`-style provider variables) or the
  OCI CLI configuration. Provider credentials are never Terraform variables.
- The OCI CLI (`oci`) on `PATH` for the helm apply: the `kubernetes` and `helm` providers run
  `oci ce cluster generate-token --cluster-id <cluster_id> --region <region>`, the command a kubeconfig from
  `oci ce cluster create-kubeconfig --token-version 2.0.0` runs, with the same OCI CLI login.
- For the helm apply, a route to the public API endpoint: run it from inside `api_allowed_cidr`.
- Rights to create VCNs, OKE clusters, buckets, repositories, dynamic groups (tenancy level) and policies.
- Tenancy and compartment OCIDs; a Union org and control plane host, and the `uctl` and `kubectl` tools from the
  Union deploy page.

## Apply

Check `kubernetes_version` against `oci ce cluster-options get --cluster-option-id all` first; the default patch
version is a best guess. Set your own values in copies of the examples
([`../examples/oci/`](../examples/oci/)).

1. The infra root:
   ```bash
   terraform -chdir=oci/infra init && terraform -chdir=oci/infra apply -var-file=../../examples/oci/infra/minimal.tfvars
   ```
2. Register the cluster with Union and create the Secrets the chart reads. Neither is in Terraform, because they
   hold credentials:
   ```bash
   $(terraform -chdir=oci/infra output -raw kubeconfig_command)
   uctl selfserve provision-dataplane-resources --clusterName "$(terraform -chdir=oci/infra output -raw cluster_name)" --provider oci
   kubectl create namespace union
   kubectl create secret generic union-secret-auth -n union \
     --from-literal=client_secret=<client secret from uctl> --from-literal=app_secret=<client secret from uctl>
   ```
   Without `static_credentials_user_ocid` (Option A, the default) also create `storage-credentials`, from a customer
   secret key of a user whose group may manage objects in the two buckets (see "Storage key" below):
   ```bash
   kubectl create secret generic storage-credentials -n union \
     --from-literal=access_key_id=<access key> --from-literal=secret_key=<secret key>
   ```
   With Option B the helm root creates that Secret from the infra key.
3. The helm root, with the client ID from step 2 and your org and control plane host in its tfvars:
   ```bash
   terraform -chdir=oci/helm init && terraform -chdir=oci/helm apply -var-file=../../examples/oci/helm/minimal.tfvars
   ```

The chart does not check that `union-secret-auth` exists: without it the release waits out its 15-minute timeout
with crashlooping pods. It reads `storage-credentials` when it renders, so that Secret has to exist before step 3
(or before the next helm apply, after a key rotation).

Then create the pull secret for Union system images, as the Deploy and image-pull docs describe (not
Terraform-managed, as it holds a credential).

## State and backends

Neither root has a `backend` block: where state lives is your choice.

1. **First run, nothing configured:** both roots use local state, and `helm/` reads `../infra/terraform.tfstate`
   (`infra_state` defaults to that).
2. **Remote state (recommended):** add a `backend.tf` to both roots, then tell `helm/` where the infra state is,
   once, in its tfvars, with the same settings as the infra backend block. For a bucket on OCI's S3-compatible API:
   ```hcl
   infra_state = { backend = "s3", config = { bucket = "example-tfstate", key = "union-dataplane/oci/infra.tfstate", region = "us-ashburn-1", endpoints = { s3 = "https://examplenamespace.compat.objectstorage.us-ashburn-1.oraclecloud.com" }, skip_region_validation = true, skip_credentials_validation = true, skip_requesting_account_id = true, skip_s3_checksum = true, use_path_style = true } }
   ```
3. Both states are secrets when Option B is on: `infra/` holds the customer secret key, and `helm/` holds it again
   in the `storage-credentials` Secret. Use backends with encryption at rest and restricted access, and give the
   helm runner read-only access to the infra state.

Terraform workspaces are not supported: `helm/` reads the infra root's default workspace.

## Destroy, in reverse

```bash
terraform -chdir=oci/helm  destroy -var-file=../../examples/oci/helm/minimal.tfvars
terraform -chdir=oci/infra destroy -var-file=../../examples/oci/infra/minimal.tfvars
```

`helm/` first: it removes the chart, whose Services own OCI load balancers in the public subnet. Destroying `infra/`
first orphans those load balancers and blocks the subnet and VCN delete; recovering takes
`terraform -chdir=oci/helm state rm` of everything, and deleting the load balancers by hand. The Secrets you created
in step 2 go with the cluster.

## Inputs

`infra/`:

| Variable | Meaning |
|---|---|
| `region` (required) | OCI region identifier, for example `us-ashburn-1` |
| `tenancy_ocid`, `compartment_ocid` (required) | The tenancy (dynamic groups live there) and the compartment holding everything else |
| `name` | Prefix for every resource name (default `union-dataplane`) |
| `labels` | Extra freeform tags merged over `managed-by` and `stack` |
| `kubernetes_version` | OKE version (default `v1.34.1`) |
| `vcn_cidr`, `public_subnet_cidr`, `private_subnet_cidr` | VCN range and its two subnets (defaults `10.0.0.0/16`, `10.0.192.0/24`, `10.0.0.0/18`). The public subnet holds the API endpoint and load balancers; the private one holds the nodes and, with VCN-native pod networking, the pod IPs, so keep it at least /18 |
| `system_node_pool` | Shape, OCPUs, memory and size of the system pool (defaults: `VM.Standard.E5.Flex`, 4, 32 GB, 3 nodes) |
| `worker_node_pool` | Optional worker pool: `enabled` (default `false`), shape, OCPUs, memory, `size`, `preemptible` |
| `api_allowed_cidr`, `allow_public_api_endpoint` | Who may reach the public API endpoint (TCP 6443). Required: unset or a `/0` is rejected unless `allow_public_api_endpoint = true`, so the API is never open to any address by default |
| `static_credentials_user_ocid` | Option B: IAM user to create an S3-compatibility key for (default `null`: instance principals) |
| `fast_registration_retention_days` | Days before fast-registration objects are deleted (default 7) |

`helm/`:

| Variable | Meaning |
|---|---|
| `union_client_id` (required) | The client ID `uctl selfserve provision-dataplane-resources` printed (`global.AUTH_CLIENT_ID`); its secret is in `union-secret-auth` |
| `union_org_name` (required) | Union organization name (`global.ORG_NAME`) |
| `union_control_plane_host` (required) | The control plane host Union gave you, no scheme or port (`global.CONTROLPLANE_HOST`). The OCI deploy page documents no `<org>.union.ai` default, so none is guessed |
| `infra_state` | Where the infra state is (default: `../infra/terraform.tfstate`); see "State and backends" |

## Outputs

`infra/`: `bucket_name`, `cluster_ca_certificate`, `cluster_endpoint`, `cluster_id`, `cluster_name`,
`dynamic_group_name`, `fast_registration_bucket_name`, `helm_values` (the OCI layer of the chart values),
`image_builder_repository`, `kubeconfig_command`, `object_storage_namespace`, `region`, and for Option B
`s3_access_key` and `s3_secret_key` (sensitive). The helm root reads `cluster_endpoint`, `cluster_ca_certificate`,
`cluster_id` and `region` (its providers and their token command), `helm_values`, and for Option B `s3_access_key`
and `s3_secret_key`; the rest are for you. Use `cluster_name` for
`flyte create cluster $(terraform -chdir=oci/infra output -raw cluster_name) --pool default`.

`helm/`: `namespace`, the release namespace.

## Storage key

Storage needs an S3-compatibility key whichever option you pick: the dataplane chart (checked at 2026.10.1) has no
instance-principal mode for Object Storage, its `oci` provider always authenticates with an access key. The chart
reads it from the Secret `storage-credentials` (`storage.credentialsSecretRef` in `helm_values`). With
`static_credentials_user_ocid` set (Option B), infra creates the key and helm puts it in that Secret; the key is then
in both states. Without it, create the Secret yourself (Apply, step 2).

## Add-ons

None: the optional pieces are the worker pool and the Option B key, both infra inputs.

## Not covered, and why

- **CORS for the Code Viewer** (`https://*.unionai.cloud`, GET/HEAD, headers `*`, expose `ETag`, max age 3600): the `oracle/oci` provider has no bucket CORS resource. Manual step on both buckets per the OCI CORS docs.
- **Cluster autoscaler**: the docs give no OCI setup. Pools have fixed sizes; install the OKE cluster autoscaler yourself. For the same reason pools do not scale from zero.
- **GPU node pool**: the OCI page does not describe one, so the optional GPU pool of the shared defaults is not implemented.
- **Single-bucket option**: two buckets are the recommended path, so only that is implemented.
- **Logging backend, secrets store**: the OCI page documents neither.
- **Generic/on-prem**: not in the OCI page.
- **Image Builder registry login**: the chart's `imageBuilder.authenticationType` supports `noop`, `google`, `aws`,
  `azure` and `basic`, none of them OCI instance principals, so pushing to the private repository needs `basic` with
  an OCI auth token (`imageBuilder.basicAuth`). An auth token is a user credential, so it is not created here.
- **The auth and image-pull Secrets**: they hold credentials Union issues, so you create them (Apply, step 2) and
  they never reach Terraform state.

## Conservative readings

- Dynamic-group matching rule is the docs' `instance.compartment.id = <compartment>`, which covers every instance in the compartment, not only OKE nodes. Use a dedicated compartment. In tenancies with identity domains the dynamic group may need a `'<domain>'/` prefix.
- OCI only allows dynamic groups in the tenancy root, so `tenancy_ocid` is required.
- Object Storage lifecycle rules do not run without an `objectstorage-<region>` service policy; `oci_identity_policy.object_storage_lifecycle` adds it. This is OCI's prerequisite, not a Union requirement.
- Nodes and pods share the private /18 (VCN-native CNI allows a shared subnet); max pods per node is 31. Raise it only after checking subnet size against the pod-density math.
- System pool is 4 OCPU (8 vCPU) / 32 GB per node rather than the 4 vCPU / 16 GB minimum, since default system requests (14 vCPU, 27 GiB) exceed what three minimum nodes provide. Shape is the non-burstable E5 Flex.
- The node image lookup uses the option set `all` and filters to the cluster version, instead of the cluster-specific option set, so it resolves at plan time and does not depend on the cluster resource.
- `helm_values` sets the keys the OCI page names plus the chart keys those need to work: `storage.provider: oci`,
  `storage.authType: accesskey`, `storage.endpoint` (the tenancy's S3-compatibility endpoint,
  `https://<namespace>.compat.objectstorage.<region>.oraclecloud.com`), `storage.credentialsSecretRef` and
  `imageBuilder.defaultRepository` (the OCIR repository). The chart's defaults (`compat`, no endpoint,
  `registryName` as the repository) would send storage calls to AWS and images nowhere. The chart has no OCI
  overlay, so these are the whole cloud layer of the release's values.
- The OCIR grant is limited to the image-builder repository, where the docs grant `manage repos` on the compartment:
  Image Builder pushes every image into `imageBuilder.defaultRepository`, as its AWS setup (one ECR repository, no
  `CreateRepository`) shows.
- No service gateway is created: NAT egress reaches OCIR and Object Storage, which is what the docs require.
- The cluster CA comes from the kubeconfig OKE generates (`data.oci_containerengine_cluster_kube_config`, token
  version 2.0.0, which holds an exec entry rather than a credential): the cluster resource does not expose it. Not
  run against a live cluster; the exec command is the one OCI documents for token version 2.0.0 kubeconfigs.

## Changed from union-dataplane-tf

Outputs renamed relative to the original `union-dataplane-tf/oci`: `metadata_bucket` is now `bucket_name` and
`fast_registration_bucket` is now `fast_registration_bucket_name` (same names as the other clouds in this repo).
`cluster_endpoint`, `cluster_ca_certificate` and `helm_values` are new. The registry grant is narrower than before:
`manage repos` is limited to the image-builder repository (`where target.repo.name = ...`). `api_allowed_cidr` no
longer defaults to `0.0.0.0/0`: it is required, and an open API endpoint takes `allow_public_api_endpoint = true`.
The Helm install, a manual step there, is the `helm/` root here.

The pool variables of the original became two objects. `system_pool_shape`, `system_pool_ocpus`,
`system_pool_memory_gbs` and `system_pool_size` are `system_node_pool.shape`, `.ocpus`, `.memory_gbs` and `.size`.
`worker_pool_shape`, `worker_pool_ocpus`, `worker_pool_memory_gbs`, `worker_pool_size` and `worker_pool_preemptible` are
`worker_node_pool.shape`, `.ocpus`, `.memory_gbs`, `.size` and `.preemptible`. The original created the worker pool when
`worker_pool_size` was above 0 (default 0); now `worker_node_pool.enabled` (default `false`) does, and
`worker_node_pool.size` defaults to 1. The other defaults are unchanged.

## Differences from the sibling repo

The sibling repository, [terraform-flyte](https://github.com/unionai-oss/terraform-flyte), has no folder for this
cloud: OCI is Union-only. So every file, variable, output and provider of both roots is specific to this
repository, and there is nothing of the same name to differ in meaning.

### infra

Here and not there:

- Everything: `main.tf`, `dataplane.tf` (the product file; `flyte.tf` in the sibling's clouds) and the rest of the
  root, with the dataplane-only variables `static_credentials_user_ocid` and
  `fast_registration_retention_days`, and the outputs that feed the helm root and the Union registration
  (`dynamic_group_name`, `fast_registration_bucket_name`, `helm_values`, `image_builder_repository`,
  `object_storage_namespace`, `s3_access_key`, `s3_secret_key`). There is no `exposure.tf`, `oauth.tf` or
  `tailscale.tf`: the dataplane serves no endpoint of its own.

Same name, different meaning or default:

- None: the sibling has no OCI root.

### helm

Here and not there:

- `helm/`: the whole root, which installs the Union `dataplane` chart (`dataplane.tf`) with the variables
  `union_client_id`, `union_control_plane_host` and `union_org_name`. There is no `mcp.tf` or NVIDIA device plugin:
  the dataplane serves no endpoint, and this folder has no GPU pool.

Same name, different meaning or default:

- None: the sibling has no OCI root.

# Union dataplane on AWS (self-managed)

Terraform for a self-managed [Union.ai](https://www.union.ai/) dataplane on AWS: VPC, EKS cluster, S3 buckets, an
ECR repository and the IRSA role Union's services assume, then Union's `dataplane` Helm chart on top.

Two root modules, applied in order: `infra/` creates everything through the AWS API, then `helm/` installs the chart
(and the NVIDIA device plugin with a GPU pool) through the Kubernetes API. `helm/` reads all it needs from the state
of `infra/`; nothing is copied between the two by hand.

Validated (fmt, validate, tflint, terraform test with mock providers) but not yet applied live.

## What it creates

`infra/`:

| File | Resources | Union doc requirement |
| --- | --- | --- |
| `main.tf` | VPC (default `10.0.0.0/16`, 3x `/18` private subnets, 3x `/24` public subnets, a NAT gateway per AZ or one with `single_nat_gateway`); EKS cluster (default 1.34) with the IRSA OIDC provider, add-ons CoreDNS / VPC CNI / kube-proxy, a system node group (3x `m5.2xlarge`, fixed size), and optional worker and GPU node groups, each created with `desired_size` nodes (default 1) | Networking and IP capacity; EKS cluster; node pools |
| `dataplane.tf` | S3 `<name>-<suffix>-metadata` (versioned) and `<name>-<suffix>-fast-reg` (objects expire after 7 days), both with GET/HEAD CORS from `https://*.unionai.cloud` (Code Viewer) public access blocked and a TLS-only bucket policy; ECR repository `<name>` with scan-on-push; IRSA role `<name>-union-system` with S3 and ECR policies limited to those buckets and that repository | S3, CORS, data retention, ECR, IAM steps 1-4 |

`helm/`:

| File | Resources | Union doc requirement |
| --- | --- | --- |
| `main.tf` | The helm base, identical to `terraform-flyte/aws/helm`: the remote state of `infra/`, the `kubernetes` and `helm` providers, and with `gpu_node_pool.enabled` the NVIDIA device plugin `0.20.1` | GPU nodes |
| `dataplane.tf` | The `dataplane` chart `2026.10.1` as release `union` in namespace `union`, with the infra `helm_values`, the AWS settings (S3 through IRSA, the IRSA role annotations; see The AWS values), and your org, control plane host and client ID. `secrets.admin.create = false`: the client secret comes from a Secret you create | Deploy steps 4-5 |

Base modules: `terraform-aws-modules/vpc/aws` `6.7.3` and `terraform-aws-modules/eks/aws` `21.29.0`. The EKS
module's managed node groups attach `AmazonEC2ContainerRegistryReadOnly` to the node role, which satisfies the
requirement that kubelet can pull from ECR. Everything else is provider resources and Helm charts directly.

## Prerequisites

- Terraform `>= 1.11.0, < 2.0.0` and AWS credentials with permission to create VPC, EKS, EC2, IAM, S3 and ECR
  resources. Credentials come from the standard AWS chain (`AWS_PROFILE`, `AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`, or SSO via `aws sso login`); no credentials are Terraform inputs.
  The identity that runs the infra apply is the cluster creator admin; run the helm apply as that identity (or one
  you grant access).
- The **AWS CLI on `PATH`** for the helm apply: its Kubernetes and Helm providers fetch short-lived cluster tokens
  with `aws eks get-token`, so no cluster credential is stored.
- EC2 vCPU quota for the node groups (quotas are per instance family).
- **A route to the EKS API for the helm apply** and every `kubectl` / `flyte` step (the infra apply only talks to AWS
  APIs). The endpoint is **private by default** (`cluster_endpoint_public_access = false`). Either run those steps
  from a host inside or routed to the VPC (peering, VPN, Direct Connect, an SSM-reachable instance or a CI runner in
  the VPC), or set `cluster_endpoint_public_access = true` with `cluster_endpoint_public_access_cidrs` limited to your
  own address. For a network connected to the VPC, set `cluster_endpoint_private_access_cidrs` to its CIDRs: that
  opens 443 on the cluster security group to them, and you then run those steps from a host in those CIDRs (hosts
  inside the VPC need no rule). All three are `infra/` variables, the same as in the sibling repo.
- A Union organization and control plane host, plus `kubectl` and `uctl` for the steps between the two applies.

## Apply

```bash
terraform -chdir=aws/infra init && terraform -chdir=aws/infra apply -var-file=../../examples/aws/infra/minimal.tfvars
```

`name` is the cluster name, the ECR repository name and the prefix of every other resource; it must match the
cluster name you register with the Union control plane.

Then, before the helm apply, register the cluster and create the dataplane's credential
([deploy steps 2-3](https://www.union.ai/docs/v2/union/deployment/selfmanaged/deploy.md)), using the `cluster_name`
output: `flyte create cluster ... --pool default`, then
`uctl selfserve provision-dataplane-resources --clusterName <cluster_name> --provider aws`. It prints a client ID and
a secret; Union does not store the secret. Put the secret in the cluster yourself, so it never reaches Terraform
state:

```bash
terraform -chdir=aws/infra output -raw kubeconfig_command | sh
kubectl create namespace union
kubectl -n union create secret generic union-secret-auth \
  --from-literal=client_secret=<secret> --from-literal=app_secret=<secret>
```

Then set `union_org_name`, `union_control_plane_host` and `union_client_id` in the helm tfvars and apply:

```bash
terraform -chdir=aws/helm  init && terraform -chdir=aws/helm  apply -var-file=../../examples/aws/helm/minimal.tfvars
```

The chart does not check that `union-secret-auth` exists: without it the apply waits out its 15-minute timeout with
crash-looping pods. `flyte get cluster` confirms the registration.

Examples in `../examples/aws/`, the same scenario in both roots: `minimal.tfvars` (defaults) and
`gpu-and-spot.tfvars` (a spot worker pool and a GPU pool).

## State and backends

Neither root has a `backend` block: where state lives is your choice.

1. **First run, nothing configured:** both roots use local state, and `helm/` reads `../infra/terraform.tfstate`
   (`infra_state` defaults to that).
2. **Remote state (recommended):** add a `backend.tf` to both roots, then tell `helm/` where the infra state is,
   once, in its tfvars, with the same settings as the infra backend block:
   ```hcl
   infra_state = { backend = "s3", config = { bucket = "example-tfstate", key = "union-dataplane/aws/infra.tfstate", region = "us-east-2", use_lockfile = true } }
   ```
3. Give the helm runner read-only access to the infra state, and use backends with encryption at rest. Neither
   state holds the Union client secret (it is only in the `union-secret-auth` Secret).

Terraform workspaces are not supported: `helm/` reads the infra root's default workspace.

## Destroy, in reverse

```bash
terraform -chdir=aws/helm  destroy -var-file=../../examples/aws/helm/minimal.tfvars
terraform -chdir=aws/infra destroy -var-file=../../examples/aws/infra/minimal.tfvars
```

`helm/` first: destroying `infra/` first deletes the cluster under the releases, and the helm root then cannot reach
it; recovering takes `terraform -chdir=aws/helm state rm` of everything. The `union-secret-auth` Secret and the
`union` namespace go with the cluster. Buckets are not force-destroyed: empty them first, or the infra destroy fails
by design.

## Inputs

`infra/`:

| Variable | Meaning |
| --- | --- |
| `region` | Required. No default: nothing is hard-coded. |
| `name` | Prefix for resources and the cluster name (default `union-dataplane`). Lowercase letters, digits and single hyphens, starting with a letter, at most 29 characters (the EKS cluster IAM role prefix `<name>-cluster-` is capped at 38). |
| `system_node_pool` | `{ instance_types, node_count }`, defaults `["m5.2xlarge"]` and `3`. Burstable (t-series) types and fewer than 3 nodes are rejected. |
| `worker_node_pool` | `{ enabled, capacity_type, desired_size, instance_types, max_size, min_size }`; off by default. Enabled, it is created with `desired_size` nodes (default 1); `min_size` (default 0) and `max_size` (default 10) bound an autoscaler if you install one (`0 <= min_size <= desired_size <= max_size`). The EKS module ignores later changes to `desired_size`, so resize a running pool with the EKS console or CLI. |
| `gpu_node_pool` | Same shape (`max_size` default 4), tainted `nvidia.com/gpu=true:NoSchedule` and labelled `node-pool=gpu`, NVIDIA AMI; off by default. Enabled, `helm/` installs the NVIDIA device plugin on it. |
| `cluster_endpoint_private_access_cidrs`, `cluster_endpoint_public_access`, `cluster_endpoint_public_access_cidrs` | See Prerequisites. |
| `vpc_cidr`, `private_subnet_cidrs`, `public_subnet_cidrs`, `single_nat_gateway` | Network. Pod IPs come from the private subnets; subnets cannot be resized later. |
| `kubernetes_version` | EKS version, default `1.34`. |
| `fast_registration_expiration_days` | Code-bundle retention, default 7. |
| `tags` | Extra tags merged over `managed-by` and `stack`; applied through the provider's `default_tags`. |

`helm/`:

| Variable | Meaning |
| --- | --- |
| `infra_state` | Where the infra state is (State and backends). Default: `../infra/terraform.tfstate`. |
| `union_org_name` | Required: your Union organization (`global.ORG_NAME`). |
| `union_control_plane_host` | Required: the control plane hostname, no scheme or port (`global.CONTROLPLANE_HOST`). Copy it from your Union console or the Union deploy documentation; it is not derived from the org name. |
| `union_client_id` | Required: the client ID `uctl selfserve provision-dataplane-resources` printed (`global.AUTH_CLIENT_ID`). Its secret is in `union-secret-auth`, never here. |

## Outputs

`infra/`: `account_id`, `bucket_name` (the metadata bucket), `cluster_ca_certificate`, `cluster_endpoint`,
`cluster_name`, `ecr_repository_name`, `ecr_repository_url`, `fast_registration_bucket`, `gpu_node_pool` (the input,
for `helm/`), `gpu_node_selector` (the GPU nodes' label, for the device plugin in `helm/`), `helm_values` (the chart's AWS keys: `CLUSTER_NAME`, `AWS_ACCOUNT_ID`, `AWS_REGION`,
`METADATA_BUCKET`, `FAST_REGISTRATION_BUCKET`, `BACKEND_IAM_ROLE_ARN`, `WORKER_IAM_ROLE_ARN`, plus
`imageBuilder.registryName`), `iam_role_arn`, `kubeconfig_command`, `oidc_provider_arn`, `region`.

`helm/`: none.

## The AWS values

Union's docs install the chart with its `values.aws.yaml` overlay. `helm/dataplane.tf` does not use that file; it
sets the overlay's keys this deployment needs itself: `provider = "aws"`, `storage` (S3 in the infra region through
IRSA, which also points the image builder at the ECR registry), and the IRSA role annotation on the chart's service
accounts (`additionalServiceAccountAnnotations`) and on the task pods' accounts (`userRoleAnnotationKey` /
`userRoleAnnotationValue`). Left out: the Karpenter `do-not-disrupt` annotation (no Karpenter here), the DCGM
exporter affinity (the exporter is off by default), the AWS Secrets Manager settings (the chart's secret manager is
Kubernetes by default), and `imageBuilder.buildkit.rootless = false` (already the chart default). When you change the
chart version, compare its `values.aws.yaml` with these keys.

## Not covered, and why

- **ECR pull-through cache and `ecr.api` / `ecr.dkr` VPC interface endpoints**: the docs recommend them to relieve
  pull rate during rapid scale-up, as a mitigation, not a baseline requirement.
- **VPC CNI prefix delegation / warm-pool tuning, extra VPC CIDR blocks**: relief once pod-IP pressure appears; the
  default /18 subnets already cover the documented ~40,000 pods.
- **Cluster autoscaler / Karpenter**: the docs support autoscaling but do not prescribe one. Install the one you
  prefer; without one an enabled optional group stays at its `desired_size` (default 1), because a managed node group
  does not change size by itself, and you add the autoscaler's discovery tags yourself.
- **Persistent logs to CloudWatch**: the default FluentBit-to-metadata-bucket path needs no extra infrastructure.
- **Separate worker IAM role**: the docs allow one role for both; one role is created.
- **EBS CSI driver**: nothing in the dataplane layer uses a PersistentVolumeClaim.
- **The Union auth Secret**: created by you (Apply), because Terraform would write it to state. A check that it
  exists before the release was left out for the same reason: reading the Secret copies it into state.

## Conservative readings

- Kubernetes 1.34 is within the three most recent minors the docs require; check what your region offers.
- The docs show `eksctl --nodes 3 --node-type m5.2xlarge`; this is the system pool (fixed size 3, no taints). Task
  pods may run there by default, per the docs.
- The IRSA trust uses `system:serviceaccount:*` as in the docs, because platform services and per-project task pods
  share the role; the OIDC audience condition limits it to this cluster.
- The S3 public access block is a standard safeguard the docs do not mention.
- No bucket `force_destroy`: destroying non-empty buckets fails by design.
- No lifecycle rule on the metadata bucket; the docs point to a data-retention page without a rule for it.
- Only `global.CONTROLPLANE_HOST` is set: the chart reads the older `global.UNION_CONTROL_PLANE_HOST` only as a
  deprecated fallback.

## Changed from union-dataplane-tf

Variables renamed or folded: `cluster_name` and `bucket_prefix` became `name` (`cluster_name` is an output only);
`system_node_instance_types` / `system_node_count` became `system_node_pool`; `enable_worker_node_group` became
`worker_node_pool.enabled`, `worker_node_instance_types` `worker_node_pool.instance_types`,
`worker_node_capacity_type` `worker_node_pool.capacity_type` and `worker_node_max_size`
`worker_node_pool.max_size`; the GPU pool is now `gpu_node_pool`. `ecr_repository_name` and
`iam_role_name` are derived from `name`. `worker_node_min_size` became `worker_node_pool.min_size` (default 0), with a
separate `desired_size` (default 1) instead of creating the group at its minimum, so an enabled pool has a node
without an autoscaler. Dropped: `single_bucket` (the docs recommend two buckets so they can have different
retention). Dropped output `metadata_bucket` (now `bucket_name`). Pinned modules exactly instead of `~> 6.0` /
`~> 21.0`; provider `aws` `~> 6.59`; Terraform `>= 1.11.0, < 2.0.0` instead of exactly 1.16.6. The original stopped
at the infrastructure; the Helm install (and the device plugin) is now the `helm/` root.

## Differences from the sibling repo

The sibling `terraform-flyte/aws` deploys OSS Flyte on the same base, with the same two roots: `infra/main.tf` and
`helm/main.tf` are byte-identical.

### infra

Here and not there:

- `dataplane.tf`: the Union product layer (buckets, ECR, IRSA role).
- `tests/dataplane.tftest.hcl`: its tests.
- Variable `fast_registration_expiration_days`: only the dataplane has a fast-registration bucket.
- Outputs `ecr_repository_name`, `ecr_repository_url`, `fast_registration_bucket`, `helm_values` and
  `iam_role_arn`: inputs of the Union chart.

Same name, different meaning or default:

- `bucket_name`: here the dataplane's metadata bucket; there the bucket holding Flyte's data.
- `name`: defaults to `union-dataplane` here and `flyte` there (CONVENTIONS section 3).

### helm

Here and not there:

- `dataplane.tf`: the Union `dataplane` release.
- `tests/dataplane.tftest.hcl`: its tests.
- `tests/fixtures/minimal.json`, `tests/fixtures/gpu-and-spot.json`: the infra outputs of each example.
- Variables `union_client_id`, `union_control_plane_host` and `union_org_name`: they only fill the chart's values.

Same name, different meaning or default:

- None.

The sibling's own extras are listed in its README.

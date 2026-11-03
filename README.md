# terraform-union-dataplane

Terraform for a self-managed [Union.ai](https://www.union.ai/) dataplane on each cloud, in two applies. The
`<cloud>/infra` root builds the Kubernetes cluster and network (from the well-known upstream modules where they
exist), object storage, a container registry and the workload identity the dataplane's services use. The
`<cloud>/helm` root then installs Union's dataplane chart into that cluster, reading everything it needs from the
infra root's state; you give it only your organization (`union_org_name`, `union_control_plane_host`,
`union_client_id`) and create the auth Secret between the two applies. Union runs the control plane; you run the
dataplane.

The sibling repository [terraform-flyte](https://github.com/unionai-oss/terraform-flyte) builds the same base for
open-source Flyte; the two are maintained in lockstep ([AGENTS.md](AGENTS.md)). This repository has no exposure modes
or add-ons: the dataplane serves no endpoint of its own and connects out to the Union control plane.

## Coverage

| Cloud | Folder | Network and cluster | Status |
|---|---|---|---|
| AWS | [aws/](aws/) | terraform-aws-modules/vpc + eks | validated, not yet applied live |
| Azure | [azure/](azure/) | Azure Verified Modules: virtual network + NAT gateway + AKS managed cluster | validated, not yet applied live |
| GCP | [gcp/](gcp/) | terraform-google-modules/network + cloud-router + kubernetes-engine | validated, not yet applied live |
| CoreWeave | [coreweave/](coreweave/) | provider resources directly | validated, not yet applied live |
| Crusoe | [crusoe/](crusoe/) | provider resources directly | validated, not yet applied live |
| Nebius | [nebius/](nebius/) | provider resources directly | validated, not yet applied live |
| OCI | [oci/](oci/) | provider resources directly | validated, not yet applied live |

Not covered: generic Kubernetes (on-premises, any S3-compatible store), which has no cloud provider for Terraform to
create resources with. Each cloud README lists what it implements from Union's self-managed deployment docs, what is
left as a manual step, and what changed from the earlier `union-dataplane-tf` port.

## Layout

Every cloud folder holds two root modules, applied in this order, and one README (see [CONVENTIONS.md](CONVENTIONS.md)
sections 1 and 10):

| Root | What | Files |
|---|---|---|
| `<cloud>/infra/` | Everything created through the cloud's API: network, cluster, node pools, storage, identities | `terraform.tf` (pins), `main.tf` (the network and cluster from the upstream modules, the same text as in the sibling repository for that cloud), `dataplane.tf` (the dataplane's cloud resources: buckets, registry, identities), `variables.tf`, `outputs.tf`, `tests/` |
| `<cloud>/helm/` | Everything created through the Kubernetes API. It reads the infra root's outputs from its state; nothing is entered by hand between the two applies | `terraform.tf`, `main.tf` (the remote state, the Kubernetes and Helm providers and what every product needs in the cluster, the same text as in the sibling repository for that cloud), `dataplane.tf` (the Union `dataplane` release), `variables.tf`, `outputs.tf`, `tests/` |

`examples/<cloud>/infra/*.tfvars` and `examples/<cloud>/helm/*.tfvars` are example inputs, with the same scenario name
in both; `checks.sh` plans each of them against mock providers.

```sh
terraform -chdir=aws/infra init && terraform -chdir=aws/infra apply -var-file=../../examples/aws/infra/minimal.tfvars
# between the two: create namespace union and Secret union-secret-auth (keys client_secret, app_secret), see aws/README.md
terraform -chdir=aws/helm init && terraform -chdir=aws/helm apply -var-file=../../examples/aws/helm/minimal.tfvars
```

Edit the placeholders in the examples first. Destroy in reverse: `helm` first, then `infra`.

Provider credentials come from each cloud's own CLI login or environment variables, never from Terraform variables;
each cloud README says which.

## Checks

`./checks.sh` checks each cloud folder's layout and README, then runs, for every root: `terraform fmt -check`,
`terraform init -backend=false`, `terraform validate`, `tflint` and `terraform test` (mock providers, no
credentials), and plans every example. For each `helm/` root it also checks the contract with `infra/`: it reads only
outputs the infra root has, keeps the infra root's sensitive outputs sensitive, and its test fixtures have exactly the
infra root's output names. Then it greps every file git lists in the repository (tracked, or untracked and not
ignored; without git, all but `.git/` and the names `.gitignore` lists for state, plans and credentials, a fixed list:
the file is not read) but `checks.sh` itself (the cloud folders, `examples/`, these top-level docs, the workflows and
the lock files) for hard-coded account, subscription and tenant IDs, Nebius project and tenant IDs, tailnet names,
secrets (also in YAML and shell snippets) and private domains under a country-code TLD or one of the generic TLDs
listed in `HYGIENE_TLD` in `checks.sh` (a domain under another TLD is not caught). A hit is reported as `file:line`
and its class; the matched text is never printed. It uses Terraform 1.16.6 and TFLint 0.65.0 and fetches them (checksum-verified)
if the ones on `PATH` differ. `CLOUDS="aws azure" ./checks.sh` checks some cloud folders only. CI runs the same
script (`.github/workflows/checks.yml`).

**Nothing in this repository has been applied to a real cloud account yet.** Every folder is validated statically and
with mock-provider plans only; account-dependent facts (quotas, instance types and Kubernetes versions offered in
your region, real network reachability) are not verified.

# Credential-free mock plans: configuration behaviour only, nothing is provisioned.
mock_provider "coreweave" {}
mock_provider "random" {}

override_resource {
  target          = random_id.suffix
  override_during = plan
  values = {
    hex = "a1b2c3"
  }
}

variables {
  region = "US-EAST-04A"
}

run "names_and_labels" {
  command = plan

  variables {
    name   = "demo"
    labels = { team = "data" }
  }

  assert {
    condition     = coreweave_networking_vpc.this.name == "demo" && coreweave_cks_cluster.this.name == "demo" && coreweave_cks_cluster.this.zone == "US-EAST-04A"
    error_message = "VPC and cluster names must derive from var.name, and the zone from var.region."
  }

  assert {
    condition     = coreweave_object_storage_bucket.metadata.name == "demo-a1b2c3"
    error_message = "The bucket name must derive from var.name and the random suffix."
  }

  assert {
    condition     = local.labels == { "managed-by" = "terraform", "stack" = "demo", "team" = "data" }
    error_message = "Default labels must be merged with var.labels."
  }

  assert {
    condition     = coreweave_object_storage_bucket.metadata.tags["team"] == "data" && coreweave_object_storage_bucket.metadata.tags["stack"] == "demo"
    error_message = "Labels must be applied to the bucket as tags."
  }

  assert {
    condition     = length(coreweave_object_storage_access_key.this.attributes) == 1 && coreweave_object_storage_access_key.this.attributes["application"] == "union-dataplane"
    error_message = "The access key attributes must be the fixed application map, independent of var.labels."
  }
}

run "access_key_ignores_labels" {
  command = plan

  variables {
    labels = { "Team/Name" = "Data" }
  }

  assert {
    condition     = length(coreweave_object_storage_access_key.this.attributes) == 1 && coreweave_object_storage_access_key.this.attributes["application"] == "union-dataplane"
    error_message = "Labels with uppercase letters or slashes must not reach the access key (it would be replaced on every label change)."
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = coreweave_cks_cluster.this.pod_cidr_name == "pod cidr" && contains([for p in coreweave_networking_vpc.this.vpc_prefixes : p.name], coreweave_cks_cluster.this.pod_cidr_name)
    error_message = "The cluster must reference a pod prefix that exists on the VPC."
  }

  # The Kubernetes API is never open to any address by default (CONVENTIONS.md section 2). The public ingress has no
  # CIDR list, so private is the only restricted setting.
  assert {
    condition     = coreweave_cks_cluster.this.public == false
    error_message = "The API server must have no public ingress unless allow_public_api_endpoint is true."
  }

  # The storage-credentials secret is read by three parties that must agree on its two field names: the chart's
  # credentialsSecretRef (default keys access_key_id and secret_key), fluent-bit's env, and the Secret the helm root
  # creates (../helm/tests/dataplane.tftest.hcl checks that one against these values).
  assert {
    condition     = yamldecode(output.helm_values).storage.credentialsSecretRef == { name = "storage-credentials" }
    error_message = "storage must read the storage-credentials secret with the chart's default key names."
  }
  assert {
    condition = yamldecode(output.helm_values).fluentbit.env == [
      { name = "AWS_ACCESS_KEY_ID", valueFrom = { secretKeyRef = { name = "storage-credentials", key = "access_key_id" } } },
      { name = "AWS_SECRET_ACCESS_KEY", valueFrom = { secretKeyRef = { name = "storage-credentials", key = "secret_key" } } },
    ]
    error_message = "fluent-bit must take the key ID from access_key_id and the secret from secret_key."
  }
}

run "public_api_server_needs_explicit_opt_in" {
  command = plan

  variables {
    allow_public_api_endpoint = true
  }

  assert {
    condition     = coreweave_cks_cluster.this.public == true
    error_message = "allow_public_api_endpoint = true must turn on the API server's public ingress."
  }
}

run "with_access_key" {
  command = plan

  override_resource {
    target          = coreweave_object_storage_access_key.this
    override_during = plan
    values = {
      id         = "example-key-id"
      secret_key = "example-secret-key"
    }
  }

  # The helm root writes these two outputs into the storage-credentials Secret.
  assert {
    condition     = output.access_key_id == "example-key-id" && output.secret_key == "example-secret-key"
    error_message = "the key outputs must be the access key's ID and secret."
  }

  # The org, host and client ID are helm variables, and the key pair is in the Secret the helm root creates: none of
  # them is in the cloud layer.
  assert {
    condition     = length(setintersection(keys(yamldecode(output.helm_values)), ["host", "orgName", "global", "secrets"])) == 0
    error_message = "helm_values must leave the org, host, client ID and auth Secret settings to the helm root."
  }
  assert {
    condition     = !strcontains(output.helm_values, "example-key-id") && !strcontains(output.helm_values, "example-secret-key")
    error_message = "helm_values must carry no credentials."
  }
}

run "helm_values_wiring" {
  command = plan

  variables {
    name = "demo"
  }

  assert {
    condition     = yamldecode(output.helm_values).clusterName == "demo" && yamldecode(output.helm_values).provider == "custom"
    error_message = "helm_values must carry the cluster name and the custom provider."
  }

  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == "demo-a1b2c3" && yamldecode(output.helm_values).storage.fastRegistrationBucketName == "demo-a1b2c3" && yamldecode(output.helm_values).storage.custom.stow.config.region == "US-EAST-04A"
    error_message = "helm_values must name the bucket and use the zone as the S3 region."
  }

  assert {
    condition     = yamldecode(output.helm_values).storage.credentialsSecretRef.name == "storage-credentials"
    error_message = "helm_values must reference the storage-credentials secret."
  }
}

run "helm_values_match_resources" {
  command = plan

  variables {
    separate_fast_registration_bucket = true
  }

  assert {
    condition     = yamldecode(output.helm_values).clusterName == coreweave_cks_cluster.this.name
    error_message = "clusterName must be the cluster name."
  }

  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == coreweave_object_storage_bucket.metadata.name && yamldecode(output.helm_values).storage.custom.container == coreweave_object_storage_bucket.metadata.name
    error_message = "bucketName and the stow container must be the metadata bucket."
  }

  assert {
    condition     = yamldecode(output.helm_values).storage.fastRegistrationBucketName == coreweave_object_storage_bucket.fast_registration[0].name
    error_message = "fastRegistrationBucketName must be the separate bucket when one is requested."
  }

  assert {
    condition     = yamldecode(output.helm_values).storage.custom.stow.config.region == var.region && yamldecode(output.helm_values).storage.custom.stow.config.endpoint == output.object_storage_endpoint
    error_message = "The stow region and endpoint must be the zone and the object storage endpoint."
  }
}

run "long_name_rejected" {
  command = plan

  variables {
    name = "this-name-is-longer-than-thirty-characters"
  }

  expect_failures = [var.name]
}

run "reserved_bucket_prefix_rejected" {
  command = plan

  variables {
    name = "cw-demo"
  }

  expect_failures = [var.name]
}


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
  name   = "review"
  region = "US-EAST-04A"
}

run "defaults" {
  command = plan

  assert {
    condition     = length(coreweave_object_storage_bucket.fast_registration) == 0
    error_message = "No separate bucket expected by default."
  }

  assert {
    condition     = length(coreweave_object_storage_bucket_lifecycle_configuration.fast_registration) == 0
    error_message = "No expiry configuration expected when storage is shared."
  }

  assert {
    condition     = output.fast_registration_bucket_name == output.bucket_name
    error_message = "Shared storage must report the same bucket for both."
  }

  assert {
    condition     = coreweave_object_storage_bucket_versioning.metadata.versioning_configuration.status == "Enabled" && coreweave_object_storage_bucket_versioning.metadata.bucket == "review-a1b2c3"
    error_message = "Versioning must be Enabled on the metadata bucket."
  }
}

run "separate_bucket_gets_expiry" {
  command = plan

  variables {
    separate_fast_registration_bucket = true
    fast_registration_retention_days  = 7
  }

  assert {
    condition     = length(coreweave_object_storage_bucket.fast_registration) == 1 && coreweave_object_storage_bucket.fast_registration[0].name == "review-a1b2c3-fast-reg"
    error_message = "Exactly one separate bucket expected, named from var.name and the suffix."
  }

  assert {
    condition     = length(coreweave_object_storage_bucket_lifecycle_configuration.fast_registration) == 1 && coreweave_object_storage_bucket_lifecycle_configuration.fast_registration[0].bucket == "review-a1b2c3-fast-reg"
    error_message = "Expiry must target the separate bucket only."
  }

  assert {
    condition     = one(coreweave_object_storage_bucket_lifecycle_configuration.fast_registration[0].rule).expiration.days == 7
    error_message = "Retention must be 7 days."
  }

  assert {
    condition     = coreweave_object_storage_bucket_lifecycle_configuration.fast_registration[0].bucket != coreweave_object_storage_bucket.metadata.name
    error_message = "Expiry must never target the metadata bucket."
  }

  assert {
    condition     = output.fast_registration_bucket_name != output.bucket_name
    error_message = "A separate bucket must be reported under its own name."
  }
}

run "access_policy_covers_exactly_the_buckets" {
  command = plan

  variables {
    separate_fast_registration_bucket = true
  }

  assert {
    condition     = coreweave_object_storage_organization_access_policy.this.name == "review-a1b2c3"
    error_message = "The access policy name must derive from var.name and the suffix."
  }

  assert {
    condition     = toset(one(coreweave_object_storage_organization_access_policy.this.statements).resources) == toset(["review-a1b2c3", "review-a1b2c3/*", "review-a1b2c3-fast-reg", "review-a1b2c3-fast-reg/*"])
    error_message = "The policy must grant both buckets and their objects."
  }

  # The dataplane lists, reads, writes and deletes objects, including multipart uploads; the deploy page grants s3:*.
  assert {
    condition     = toset(one(coreweave_object_storage_organization_access_policy.this.statements).actions) == toset(["s3:*"]) && one(coreweave_object_storage_organization_access_policy.this.statements).effect == "Allow"
    error_message = "The policy must allow every S3 action on the buckets, as the deploy page does."
  }
}

run "invalid_retention_rejected" {
  command = plan

  variables {
    fast_registration_retention_days = 0
  }

  expect_failures = [var.fast_registration_retention_days]
}

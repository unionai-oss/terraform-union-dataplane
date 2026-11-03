# Dataplane layer (dataplane.tf): buckets, ECR, IRSA role and the helm_values output the helm root installs the
# chart with. Plans against mock providers; nothing is created.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["zone-a", "zone-b", "zone-c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = format("%012d", 1)
      arn        = format("arn:aws:iam::%012d:user/test", 1)
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = format("arn:aws:iam::%012d:role/test", 1)
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "random" {}

# The suffix is computed; fix it so the bucket names are known at plan time.
override_resource {
  target          = random_id.suffix
  override_during = plan
  values = {
    hex = "abcd1234"
  }
}

# The role ARN is computed at apply time; the helm_values assertions need a value at plan time.
override_resource {
  target          = aws_iam_role.union_system
  override_during = plan
  values = {
    arn = format("arn:aws:iam::%012d:role/test-dp-union-system", 1)
  }
}

# Bucket ids and ARNs, the repository ARN and the OIDC provider ARN are computed. Known, distinct values let the
# tests read the policy documents (which are otherwise only known after apply) and tell the buckets apart.
override_resource {
  target          = aws_s3_bucket.this["metadata"]
  override_during = plan
  values = {
    id  = "metadata-id"
    arn = "arn:aws:s3:::metadata-bucket"
  }
}

override_resource {
  target          = aws_s3_bucket.this["fast_reg"]
  override_during = plan
  values = {
    id  = "fast-reg-id"
    arn = "arn:aws:s3:::fast-reg-bucket"
  }
}

override_resource {
  target          = aws_ecr_repository.image_builder
  override_during = plan
  values = {
    arn = format("arn:aws:ecr:us-east-2:%012d:repository/test-dp", 1)
  }
}

override_resource {
  target          = module.eks.aws_iam_openid_connect_provider.oidc_provider
  override_during = plan
  values = {
    arn = format("arn:aws:iam::%012d:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/TEST", 1)
    url = "oidc.eks.us-east-2.amazonaws.com/id/TEST"
  }
}

# module.eks.oidc_provider (the :aud and :sub condition keys) is derived from the cluster's OIDC issuer.
override_resource {
  target          = module.eks.aws_eks_cluster.this
  override_during = plan
  values = {
    identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-2.amazonaws.com/id/TEST" }] }]
    certificate_authority = [{ data = "Y2E=" }]
  }
}

variables {
  name   = "test-dp"
  region = "us-east-2"
}

run "defaults" {
  command = plan

  # Every check on these inputs shares one plan: each run block re-plans the whole root.
  assert {
    condition     = startswith(aws_s3_bucket.this["metadata"].bucket, "test-dp-abcd1234-") && endswith(aws_s3_bucket.this["metadata"].bucket, "-metadata")
    error_message = "metadata bucket name is <name>-<suffix>-metadata"
  }

  assert {
    condition     = startswith(aws_s3_bucket.this["fast_reg"].bucket, "test-dp-") && endswith(aws_s3_bucket.this["fast_reg"].bucket, "-fast-reg")
    error_message = "fast-registration bucket name is <name>-<suffix>-fast-reg"
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.metadata.versioning_configuration).status == "Enabled"
    error_message = "the metadata bucket is versioned"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_lifecycle_configuration.fast_reg.rule : one(r.expiration).days]) == 7
    error_message = "fast-registration objects expire after 7 days by default"
  }

  assert {
    condition     = alltrue([for c in aws_s3_bucket_cors_configuration.this : anytrue([for r in c.cors_rule : contains(r.allowed_origins, "https://*.unionai.cloud")])])
    error_message = "both buckets allow the Union Code Viewer origin"
  }

  assert {
    condition     = alltrue([for b in aws_s3_bucket_public_access_block.this : b.block_public_acls && b.restrict_public_buckets])
    error_message = "buckets block public access"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.fast_reg.bucket == "fast-reg-id"
    error_message = "the expiry rule applies to the fast-registration bucket and never the metadata bucket"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.fast_reg.rule) == 1 && length(one(aws_s3_bucket_lifecycle_configuration.fast_reg.rule).filter) == 1
    error_message = "one rule, with an empty filter so it covers the whole fast-registration bucket"
  }

  assert {
    condition     = toset(keys(aws_s3_bucket_policy.this)) == toset(["metadata", "fast_reg"])
    error_message = "both buckets get a bucket policy"
  }

  assert {
    condition = (
      one(data.aws_iam_policy_document.bucket["metadata"].statement).effect == "Deny" &&
      one(data.aws_iam_policy_document.bucket["metadata"].statement).actions == toset(["s3:*"]) &&
      one(data.aws_iam_policy_document.bucket["metadata"].statement).resources == toset(["arn:aws:s3:::metadata-bucket", "arn:aws:s3:::metadata-bucket/*"]) &&
      one(one(data.aws_iam_policy_document.bucket["metadata"].statement).principals).identifiers == toset(["*"]) &&
      one(one(data.aws_iam_policy_document.bucket["metadata"].statement).condition).test == "Bool" &&
      one(one(data.aws_iam_policy_document.bucket["metadata"].statement).condition).variable == "aws:SecureTransport" &&
      toset(one(one(data.aws_iam_policy_document.bucket["metadata"].statement).condition).values) == toset(["false"])
    )
    error_message = "the metadata bucket denies s3:* to everyone when aws:SecureTransport is false, on the bucket and its objects"
  }

  assert {
    condition = (
      one(data.aws_iam_policy_document.bucket["fast_reg"].statement).effect == "Deny" &&
      one(data.aws_iam_policy_document.bucket["fast_reg"].statement).actions == toset(["s3:*"]) &&
      one(data.aws_iam_policy_document.bucket["fast_reg"].statement).resources == toset(["arn:aws:s3:::fast-reg-bucket", "arn:aws:s3:::fast-reg-bucket/*"]) &&
      one(one(data.aws_iam_policy_document.bucket["fast_reg"].statement).principals).identifiers == toset(["*"]) &&
      one(one(data.aws_iam_policy_document.bucket["fast_reg"].statement).condition).test == "Bool" &&
      one(one(data.aws_iam_policy_document.bucket["fast_reg"].statement).condition).variable == "aws:SecureTransport" &&
      toset(one(one(data.aws_iam_policy_document.bucket["fast_reg"].statement).condition).values) == toset(["false"])
    )
    error_message = "the fast_reg bucket denies s3:* to everyone when aws:SecureTransport is false, on the bucket and its objects"
  }

  assert {
    condition     = one(data.aws_iam_policy_document.trust.statement).actions == toset(["sts:AssumeRoleWithWebIdentity"])
    error_message = "the role is assumed with a web identity token"
  }

  assert {
    condition     = one(one(data.aws_iam_policy_document.trust.statement).principals).type == "Federated" && one(one(data.aws_iam_policy_document.trust.statement).principals).identifiers == toset([module.eks.oidc_provider_arn])
    error_message = "only this cluster's OIDC provider may assume the role"
  }

  assert {
    condition = (
      module.eks.oidc_provider == "oidc.eks.us-east-2.amazonaws.com/id/TEST" &&
      length(one(data.aws_iam_policy_document.trust.statement).condition) == 2 &&
      one([for c in one(data.aws_iam_policy_document.trust.statement).condition : c if endswith(c.variable, ":aud")]).test == "StringEquals" &&
      toset(one([for c in one(data.aws_iam_policy_document.trust.statement).condition : c if endswith(c.variable, ":aud")]).values) == toset(["sts.amazonaws.com"]) &&
      one([for c in one(data.aws_iam_policy_document.trust.statement).condition : c if endswith(c.variable, ":aud")]).variable == "${module.eks.oidc_provider}:aud"
    )
    error_message = "the audience condition requires sts.amazonaws.com from this cluster's provider"
  }

  assert {
    condition = (
      one([for c in one(data.aws_iam_policy_document.trust.statement).condition : c if endswith(c.variable, ":sub")]).test == "StringLike" &&
      toset(one([for c in one(data.aws_iam_policy_document.trust.statement).condition : c if endswith(c.variable, ":sub")]).values) == toset(["system:serviceaccount:*"]) &&
      one([for c in one(data.aws_iam_policy_document.trust.statement).condition : c if endswith(c.variable, ":sub")]).variable == "${module.eks.oidc_provider}:sub"
    )
    error_message = "the subject condition limits the role to Kubernetes service accounts of this cluster's provider"
  }

  assert {
    condition = (
      one([for s in data.aws_iam_policy_document.access.statement : s if s.sid == "S3BucketAccess"]).resources == toset(["arn:aws:s3:::metadata-bucket", "arn:aws:s3:::metadata-bucket/*", "arn:aws:s3:::fast-reg-bucket", "arn:aws:s3:::fast-reg-bucket/*"]) &&
      length(one([for s in data.aws_iam_policy_document.access.statement : s if s.sid == "S3BucketAccess"]).resources) == 4
    )
    error_message = "S3 access covers exactly the two buckets and their objects"
  }

  assert {
    condition     = one([for s in data.aws_iam_policy_document.access.statement : s if s.sid == "ECRReadWrite"]).resources == toset([aws_ecr_repository.image_builder.arn])
    error_message = "ECR push and pull is limited to the image builder repository"
  }

  # Exact action lists: a missing action breaks the chart (no listing, no image push), an extra one widens the role.
  assert {
    condition     = toset([for s in data.aws_iam_policy_document.access.statement : s.sid]) == toset(["S3BucketAccess", "ECRAuth", "ECRReadWrite"]) && length(data.aws_iam_policy_document.access.statement) == 3
    error_message = "the access policy has exactly the S3, ECR auth and ECR read/write statements"
  }

  assert {
    condition     = one([for s in data.aws_iam_policy_document.access.statement : s if s.sid == "S3BucketAccess"]).actions == toset(["s3:DeleteObject*", "s3:GetObject*", "s3:ListBucket", "s3:PutObject*"])
    error_message = "S3 access is exactly list, get, put and delete on objects, nothing broader such as s3:*"
  }

  assert {
    condition = one([for s in data.aws_iam_policy_document.access.statement : s if s.sid == "ECRReadWrite"]).actions == toset([
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ])
    error_message = "ECR access is exactly image pull and push, nothing broader such as ecr:*"
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.access.statement : alltrue([for a in s.actions : !endswith(a, ":*") && a != "*"])]) && alltrue([for s in data.aws_iam_policy_document.access.statement : contains([null, "Allow"], s.effect) && try(length(s.not_actions), 0) == 0 && try(length(s.not_resources), 0) == 0])
    error_message = "Allow statements only (the default effect), with no service-wide wildcard action, NotAction or NotResource"
  }

  assert {
    condition     = one([for s in data.aws_iam_policy_document.access.statement : s if s.sid == "ECRAuth"]).resources == toset(["*"]) && one([for s in data.aws_iam_policy_document.access.statement : s if s.sid == "ECRAuth"]).actions == toset(["ecr:GetAuthorizationToken"])
    error_message = "the only wildcard resource is the ECR auth token call"
  }

  assert {
    condition     = aws_ecr_repository.image_builder.name == "test-dp" && one(aws_ecr_repository.image_builder.image_scanning_configuration).scan_on_push
    error_message = "the ECR repository is named after var.name and scans on push"
  }

  assert {
    condition     = aws_iam_role.union_system.name == "test-dp-union-system"
    error_message = "the IRSA role is named after var.name"
  }
}

run "helm_values" {
  command = plan

  variables {
    fast_registration_expiration_days = 3
  }

  assert {
    condition     = yamldecode(output.helm_values).global.CLUSTER_NAME == module.eks.cluster_name
    error_message = "helm_values carries the cluster name"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.AWS_REGION == "us-east-2"
    error_message = "helm_values carries the region"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.BACKEND_IAM_ROLE_ARN == yamldecode(output.helm_values).global.WORKER_IAM_ROLE_ARN
    error_message = "one role serves backend and worker"
  }

  # Every key equals the resource attribute it is documented to carry.
  assert {
    condition     = yamldecode(output.helm_values).global.AWS_ACCOUNT_ID == data.aws_caller_identity.current.account_id
    error_message = "AWS_ACCOUNT_ID is the caller's account"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.METADATA_BUCKET == aws_s3_bucket.this["metadata"].bucket
    error_message = "METADATA_BUCKET is the metadata bucket"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.FAST_REGISTRATION_BUCKET == aws_s3_bucket.this["fast_reg"].bucket
    error_message = "FAST_REGISTRATION_BUCKET is the fast-registration bucket"
  }

  assert {
    condition     = yamldecode(output.helm_values).global.BACKEND_IAM_ROLE_ARN == aws_iam_role.union_system.arn && yamldecode(output.helm_values).global.WORKER_IAM_ROLE_ARN == aws_iam_role.union_system.arn
    error_message = "both IAM role keys carry the IRSA role ARN"
  }

  assert {
    condition     = yamldecode(output.helm_values).imageBuilder.registryName == aws_ecr_repository.image_builder.name
    error_message = "imageBuilder.registryName is the ECR repository"
  }

  assert {
    condition     = toset(keys(yamldecode(output.helm_values).global)) == toset(["CLUSTER_NAME", "AWS_ACCOUNT_ID", "AWS_REGION", "METADATA_BUCKET", "FAST_REGISTRATION_BUCKET", "BACKEND_IAM_ROLE_ARN", "WORKER_IAM_ROLE_ARN"])
    error_message = "helm_values carries exactly these global keys: the org, control plane host and client ID are the helm root's"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_lifecycle_configuration.fast_reg.rule : one(r.expiration).days]) == 3
    error_message = "fast_registration_expiration_days is honoured"
  }
}

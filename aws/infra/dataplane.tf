# The Union dataplane layer on top of the base in main.tf: object storage, the image registry and the IRSA role
# the Union Helm chart's service accounts assume. The chart itself is installed by ../helm/dataplane.tf, from the
# helm_values output.

locals {
  metadata_bucket = "${var.name}-${random_id.suffix.hex}-metadata"
  fast_reg_bucket = "${var.name}-${random_id.suffix.hex}-fast-reg"

  buckets = {
    metadata = local.metadata_bucket
    fast_reg = local.fast_reg_bucket
  }
}

resource "aws_s3_bucket" "this" {
  # One bucket for execution metadata, one for code bundles, so they can have different retention.
  for_each = local.buckets

  bucket = each.value
}

resource "aws_s3_bucket_public_access_block" "this" {
  # Both buckets: nothing here is ever public.
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning is recommended on the metadata bucket only.
resource "aws_s3_bucket_versioning" "metadata" {
  bucket = aws_s3_bucket.this["metadata"].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  # Code Viewer in the Union UI fetches code bundles straight from S3, so both buckets allow its origin.
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["https://*.unionai.cloud"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# Refuse plain-HTTP access to both buckets.
data "aws_iam_policy_document" "bucket" {
  for_each = aws_s3_bucket.this

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  policy = data.aws_iam_policy_document.bucket[each.key].json

  # The public access block and the policy are both bucket-level writes that S3 rejects when they race.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Docs: a TTL on fast-registration objects bounds cost.
resource "aws_s3_bucket_lifecycle_configuration" "fast_reg" {
  bucket = aws_s3_bucket.this["fast_reg"].id

  rule {
    id     = "expire-code-bundles"
    status = "Enabled"

    filter {}

    expiration {
      days = var.fast_registration_expiration_days
    }
  }
}

resource "aws_ecr_repository" "image_builder" {
  name = var.name

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Platform services run in the dataplane namespace and task pods in per-project namespaces, and both assume this
# role, hence the wildcard on the service-account subject (as given in the Union docs). The audience condition
# still limits it to this cluster's OIDC provider.
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:*"]
    }
  }
}

resource "aws_iam_role" "union_system" {
  name               = "${var.name}-union-system"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "access" {
  statement {
    sid       = "S3BucketAccess"
    actions   = ["s3:DeleteObject*", "s3:GetObject*", "s3:ListBucket", "s3:PutObject*"]
    resources = flatten([for b in aws_s3_bucket.this : [b.arn, "${b.arn}/*"]])
  }

  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRReadWrite"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.image_builder.arn]
  }
}

resource "aws_iam_role_policy" "access" {
  name   = "union-access"
  role   = aws_iam_role.union_system.id
  policy = data.aws_iam_policy_document.access.json
}

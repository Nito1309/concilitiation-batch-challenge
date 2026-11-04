# Data bucket for the batch pipeline. One bucket, five logical prefixes.
# No placeholder objects: S3 has no folders, and a zero-byte object at `inbox/`
# would be a real write that fires the notification wired in Github issue 3.6
# https://github.com/Nito1309/conciliacion-batch-challenge/issues/7


# --- Data bucket -------------------------------------------------------------
# Name: S3 bucket names are unique across ALL AWS accounts, so a literal name
# collides on a real account even though an emulator accepts it. `var.bucket_name`
# lets a caller pin an explicit name (deterministic policies, imported state);
# when it is empty we derive "<project>-<environment>-<6 hex>" from a random_id,
# which is stable because the value is persisted in state, not recomputed.
#
# count: makes the random_id exist only in the derived case, so supplying an
# explicit name creates zero random resources and leaves nothing unused in state.
# A count-ed resource is addressed by index; `one(...[*].hex)` reads it safely
# whether the instance exists or not, avoiding index errors when count is 0.
resource "random_id" "bucket_suffix" {
  count       = var.bucket_name == "" ? 1 : 0
  byte_length = 3
}

resource "aws_s3_bucket" "data" {
  bucket        = local.bucket_name
  force_destroy = var.environment == "lab"
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    # Fully managed by S3, saving KMS extra costs (no roles yet)
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id
  # put-bucket-acl or put-bucket-policy can expose the bucket, making it public
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output that will be migrated to outputs.tf later
output "s3_bucket_name" {
  description = "Real name of the data bucket, after any derivation."
  value       = aws_s3_bucket.data.id
}


locals {

  # DB
  db_parts = split(":", var.db_endpoint)
  db_host  = local.db_parts[0]
  db_port  = tonumber(local.db_parts[1])

  name_prefix = "${var.project}-${var.environment}"

  # S3
  # Caller-supplied name wins; otherwise prefix + trailing random suffix.
  # setting a non-empty bucket_name on a live stack is a bucket replacement — and force_destroy is only enable in lab
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${local.name_prefix}-${one(random_id.bucket_suffix[*].hex)}"

  # IAM + ECS
  log_group_name = "/ecs/${local.name_prefix}-app"

  # EventBridge Scheduler
  # 3.6 pins the dispatcher's invoke permission to this schedule ARN, so 3.7
  # must create the schedule with exactly this name in the "default" group.
  dispatch_schedule_name = "${local.name_prefix}-daily"

  # Email notifier will iterate it
  s3_prefixes = {
    inbox   = "inbox/"
    raw     = "raw/"
    data    = "data/"
    reports = "reports/"
    logs    = "logs/"
  }

  common_tags = merge(
    { Project = var.project, Environment = var.environment, ManagedBy = "terraform" },
    var.tags,
  )
}


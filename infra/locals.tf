locals {
  db_parts = split(":", var.db_endpoint)
  db_host  = local.db_parts[0]
  db_port  = tonumber(local.db_parts[1])

  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    { Project = var.project, Environment = var.environment, ManagedBy = "terraform" },
    var.tags,
  )
}


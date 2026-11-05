# Batch job, not a service.
#
# The app starts, does its work and exits. A service would read that exit as a
# crash and restart it in a loop, so this file has no aws_ecs_service on
# purpose: every run is one `RunTask` call, and each call is parameterised with
# containerOverrides (RUN_MODE, PAYLOAD, INPUT_KEY) instead of a new deploy.
#
# Where the network lives: a task definition cannot carry subnets, a security
# group or the public-IP flag. Those are arguments of the RunTask call itself,
# so section 3.5 of docs/verification.md shows them and the dispatcher (3.6)
# passes them. This file owns the part that is static: the task security group.

# Somewhere for the agent to write stdout/stderr. Retention is short on
# purpose: the app also emits its own JSON events, so these logs are the
# fallback, not the record.
resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = 14
}

resource "aws_ecs_cluster" "app" {
  name = local.name_prefix

  # Cluster-level metrics (cpu/mem per task) in CloudWatch. Off by default
  # because CloudWatch charges per custom metric.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# No ingress rules: nothing connects INTO a task. The egress rules below are the
# whole network policy, which makes it readable at a glance.
resource "aws_security_group" "task" {
  name        = "${local.name_prefix}-task"
  description = "Batch task: outbound to the database and to S3 only."
  vpc_id      = var.vpc_id
}

output "cluster_name" {
  description = "Cluster the dispatcher Lambda calls RunTask on (3.6)."
  value       = aws_ecs_cluster.app.name
}

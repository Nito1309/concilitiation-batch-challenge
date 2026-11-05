# =============================================================================
# The failure path: a task stops, someone is told.
#
# ECS publishes a `Task State Change` event for every task it runs. The rule
# below keeps the interesting ones -- this cluster, terminal state -- and hands
# them to the notifier, which turns the event into an email. Nothing polls, and
# nothing needs to know a run happened until it goes wrong.
# =============================================================================

# One verified address is enough for one recipient, and it avoids DNS entirely:
# a domain identity would need Route 53 records and DKIM before a single message
# could be sent, which is a lot of moving parts for an internal alert.
# ses (v1) rather than sesv2: the v2 resource reads its tags back after create,
# and Floci returns an identity ARN with an empty account field, which the tag
# API rejects. The v1 resource has nothing to read back.
resource "aws_ses_email_identity" "sender" {
  email = var.notification_email_from
}

# The filter is the whole design. `lastStatus` is the only field that says a task
# is over, and `clusterArn` is what keeps the rule from firing for every task in
# the account.
resource "aws_cloudwatch_event_rule" "task_stopped" {
  name        = "${local.name_prefix}-task-stopped"
  description = "Any task of this cluster reaching STOPPED."

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Task State Change"]
    detail = {
      clusterArn = [aws_ecs_cluster.app.arn]
      lastStatus = ["STOPPED"]
    }
  })
}


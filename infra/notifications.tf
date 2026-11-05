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

resource "aws_cloudwatch_event_target" "notifier" {
  rule = aws_cloudwatch_event_rule.task_stopped.name
  arn  = aws_lambda_function.notifier.arn

  # No `input` and no `input_transformer`: the notifier wants the event exactly
  # as ECS wrote it, because stopCode, stoppedReason and exitCode are all in it.
}

# EventBridge needs the right to invoke, stated on the function side. Without it
# the rule still matches and the target still exists -- the invocation is what
# fails, which is the least visible kind of broken.
resource "aws_lambda_permission" "events_notifier" {
  statement_id  = "AllowEventBridgeTaskStopped"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.task_stopped.arn
}

# EventBridge invokes asynchronously, so an exception is not returned to anyone:
# Lambda retries twice and then drops the event. This queue is what survives that
# drop -- without it a crashing notifier is indistinguishable from a quiet day.
resource "aws_sqs_queue" "notifier_dlq" {
  name                      = "${local.name_prefix}-notifier-dlq"
  message_retention_seconds = 1209600 # 14 days, same as the log groups
  sqs_managed_sse_enabled   = true

  # No redrive_policy here, deliberately. maxReceiveCount lives on a queue that a
  # consumer reads, so that a consumer which keeps failing stops seeing the
  # message; it is the setting that turns a work queue into a source for its own
  # DLQ. This queue is already the destination -- Lambda writes, a human reads,
  # and the message has been received at most once -- so a receive count would
  # never reach its limit. The redrive would be a manual `start-message-move-task`
  # after the bug is fixed, not a policy.
}

# The Lambda service writes the destination, using the function's own role, so
# the role needs to send to this queue. It is a separate statement from the SES
# one on purpose: sending email and preserving a failed event are different jobs.
data "aws_iam_policy_document" "notifier_dlq" {
  statement {
    sid       = "FailedInvocationDestination"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.notifier_dlq.arn]
  }
}

resource "aws_iam_role_policy" "notifier_dlq" {
  name   = "notifier-dlq"
  role   = aws_iam_role.notifier.name
  policy = data.aws_iam_policy_document.notifier_dlq.json
}

resource "aws_lambda_function_event_invoke_config" "notifier" {
  function_name                = aws_lambda_function.notifier.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600

  destination_config {
    on_failure {
      destination = aws_sqs_queue.notifier_dlq.arn
    }
  }
}

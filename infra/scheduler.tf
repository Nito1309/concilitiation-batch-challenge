# =============================================================================
# One schedule: every day at 05:00 in Mexico City.
#
# Scheduler, not an EventBridge rule. A rule listens on a bus and its cron is
# read in UTC; a schedule carries its own timezone, retries and role, and
# invokes the target directly. 05:00 CDMX is 11:00 UTC in winter and 10:00 in
# summer, so a UTC cron would run the batch one or two hours off half the year.
# =============================================================================

# The role Scheduler assumes. Separate from the dispatcher's role on purpose:
# that one says what the function may do once it is running, this one says who
# may start it.
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name_prefix}-scheduler"
  description        = "EventBridge Scheduler: invoke the dispatcher on time."
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

# One function, one action. The condition is the confused-deputy guard: this
# role only works for this schedule, not for any other schedule that manages to
# assume it.
#
# The schedule ARN is built from local.dispatch_schedule_name rather than from
# aws_scheduler_schedule.daily.arn, because the schedule's target already points
# at this role and referencing it back would be a cycle. The 3.6 invoke
# permission is pinned to the same string, so the two cannot drift apart.
data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    sid       = "InvokeDispatcher"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.dispatcher.arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:scheduler:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:schedule/default/${local.dispatch_schedule_name}"
      ]
    }
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "scheduler-invoke"
  role   = aws_iam_role.scheduler.name
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

# Where an invocation that never succeeded ends up. Scheduler retries on its own
# before giving up, so without a queue a lost run leaves no trace anywhere.
resource "aws_sqs_queue" "scheduler_dlq" {
  name                      = "${local.name_prefix}-scheduler-dlq"
  message_retention_seconds = 1209600 # 14 days, same as the log groups
  sqs_managed_sse_enabled   = true
}


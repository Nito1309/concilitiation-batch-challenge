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


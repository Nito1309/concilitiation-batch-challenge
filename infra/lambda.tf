# =============================================================================
# Two Lambdas, one job each:
#   dispatcher -> turns a schedule tick into an ECS RunTask call   (3.7 sends it)
#   notifier   -> turns an S3 object arrival into an email         (3.8 sends it)
#
# Both handlers are stubs: they log the event and return. 3.6 is about the
# plumbing around them -- packaging, size, timeout, logging and, above all,
# who is allowed to invoke them. The work itself belongs to the container.
# =============================================================================

# The zip root becomes /var/task inside the function, so "handlers" must be a
# directory at the top: handler = "handlers.dispatcher.handler".
data "archive_file" "handlers" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../.build/handlers.zip"
}

# One group per function. Lambda creates "/aws/lambda/<name>" on the first
# invocation if it is missing -- with no retention, i.e. forever. Creating it
# here, and having the function depend on it, is what keeps two weeks.
resource "aws_cloudwatch_log_group" "dispatcher" {
  name              = "/aws/lambda/${local.name_prefix}-dispatcher"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "notifier" {
  name              = "/aws/lambda/${local.name_prefix}-notifier"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_function" "dispatcher" {
  function_name = "${local.name_prefix}-dispatcher"
  description   = "Starts one reconciliation task per run (stub: logs the event)."
  role          = aws_iam_role.dispatcher.arn

  runtime          = "python3.12"
  handler          = "handlers.dispatcher.handler"
  filename         = data.archive_file.handlers.output_path
  source_code_hash = data.archive_file.handlers.output_base64sha256

  memory_size = 256
  timeout     = 30

  # Everything RunTask needs at call time. A Lambda only carries strings, so
  # the subnet list travels as "a,b" and the handler splits it.
  #
  # TASK_DEFINITION is the family without a revision on purpose: RunTask then
  # starts the latest ACTIVE revision, and a new image deployed in 3.5 is
  # picked up without touching this function.
  environment {
    variables = {
      CLUSTER_NAME    = aws_ecs_cluster.app.name
      TASK_DEFINITION = aws_ecs_task_definition.app.family
      SUBNETS         = join(",", var.subnet_ids)
      SECURITY_GROUPS = aws_security_group.task.id
    }
  }

  tags = local.common_tags

  depends_on = [aws_cloudwatch_log_group.dispatcher]
}

resource "aws_lambda_function" "notifier" {
  function_name = "${local.name_prefix}-notifier"
  description   = "Emails the outcome of a task: exitCode, stopCode, stoppedReason."
  role          = aws_iam_role.notifier.arn

  runtime          = "python3.12"
  handler          = "handlers.notifier.handler"
  filename         = data.archive_file.handlers.output_path
  source_code_hash = data.archive_file.handlers.output_base64sha256

  memory_size = 128

  # Default is 3s. Calling SES takes longer than that on a cold start, and a
  # timeout would surface as a failed send rather than a slow one.
  timeout = 10

  environment {
    variables = {
      SES_SENDER     = var.notification_email_from
      SES_RECIPIENT  = var.notification_email_to
      LOG_GROUP_NAME = local.log_group_name
      BUCKET_NAME    = local.bucket_name
    }
  }

  tags = local.common_tags

  depends_on = [aws_cloudwatch_log_group.notifier]
}

# EventBridge Scheduler is the only principal allowed to invoke the dispatcher.
# source_arn narrows it to one schedule: without it, any schedule in any
# account that learns the function name could start tasks.
resource "aws_lambda_permission" "scheduler_dispatcher" {
  statement_id  = "AllowSchedulerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = "arn:aws:scheduler:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:schedule/default/${local.dispatch_schedule_name}"
}

# S3 is the only principal allowed to invoke the notifier, and only for this
# bucket. source_account is required alongside source_arn: without it any
# account's bucket could point at this function.
resource "aws_lambda_permission" "s3_notifier" {
  statement_id   = "AllowS3InboxInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.notifier.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.data.arn
  source_account = data.aws_caller_identity.current.account_id
}

# A bucket holds one notification configuration; a second resource here would
# silently replace this one, so it is a single block with a single filter.
#
# The prefix filter is what keeps the flow quiet: the app writes to data/ and
# reports/ on every run, and only inbox/ is a human asking for an email.
resource "aws_s3_bucket_notification" "data" {
  bucket = aws_s3_bucket.data.id

  lambda_function {
    id                  = "inbox-to-notifier"
    lambda_function_arn = aws_lambda_function.notifier.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = local.s3_prefixes.inbox
  }

  # S3 validates the destination at write time by reading the function's
  # policy. Without the permission already in place the bucket rejects the
  # whole configuration.
  depends_on = [aws_lambda_permission.s3_notifier]
}

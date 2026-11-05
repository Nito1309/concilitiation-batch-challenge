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

  tags = local.common_tags

  depends_on = [aws_cloudwatch_log_group.dispatcher]
}


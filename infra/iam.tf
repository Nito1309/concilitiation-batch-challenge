# IAM in this stack
#
# A role is two things, and Terraform keeps them in separate resources:
#   assume_role_policy -> the trust policy: which service may assume the role
#   *_policy           -> the permissions: what the assumed identity may then do
# A missing trust policy fails with "not authorized to perform sts:AssumeRole";
# missing permissions fail later, on the first real call, with AccessDenied.

# Who may assume the ECS roles: the ECS agent, never a human and never a key.
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role. The ECS agent assumes it before the container exists, so it is
# what pulls the image, opens the log stream and resolves the DB secret.
resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-task-exec"
  description        = "ECS agent: pull image, write logs, read DB secret."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Image actions are scoped to this stack's repository. ecr:GetAuthorizationToken
# is the exception: it issues a registry token for the whole account and has no
# ARN form, so it is the only Resource "*" in the file.
data "aws_iam_policy_document" "task_exec_ecr" {
  statement {
    sid       = "PullAppImage"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = [aws_ecr_repository.app.arn]
  }
  statement {
    sid       = "EcrAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # account-level action, no ARN form exists
  }
}

resource "aws_iam_role_policy" "task_exec_ecr" {
  name   = "task-exec-ecr"
  role   = aws_iam_role.task_execution.name
  policy = data.aws_iam_policy_document.task_exec_ecr.json
}

# Scoped to the log group created in 3.5 (ecs.tf). logs:CreateLogGroup is not
# granted on purpose: it only works with Resource "*", and creating the group is
# Terraform's job, not the agent's.
data "aws_iam_policy_document" "task_exec_logs" {
  statement {
    sid     = "WriteTaskLogs"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}:*"
    ]
  }
}

resource "aws_iam_role_policy" "task_exec_logs" {
  name   = "task-exec-logs"
  role   = aws_iam_role.task_execution.name
  policy = data.aws_iam_policy_document.task_exec_logs.json
}

# The agent reads the secret once and injects it into the container as
# environment variables, which is why the permission sits here and not on the
# task role. Scoped to that one secret ARN from bootstrap, not to secretsmanager:*.
data "aws_iam_policy_document" "task_exec_secret" {
  statement {
    sid       = "ReadDbCredentials"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "task_exec_secret" {
  name   = "task-exec-secret"
  role   = aws_iam_role.task_execution.name
  policy = data.aws_iam_policy_document.task_exec_secret.json
}

# Task role. Same trust policy as the execution role, completely different
# permissions: this one is assumed by the process inside the container. Swapping
# the two is the classic mistake: a wrong execution role leaves the task in
# PENDING with no app logs, a wrong task role starts the container and then fails
# with AccessDenied.
resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-task"
  description        = "Application runtime: read and write its own S3 prefixes."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Two statements because the two ARN shapes differ: object actions take
# "<bucket>/*", the bucket action takes "<bucket>". Nothing outside the data
# bucket is reachable from the app code.
data "aws_iam_policy_document" "task_s3" {
  statement {
    sid       = "ReadWriteObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn]
  }
}

resource "aws_iam_role_policy" "task_s3" {
  name   = "task-s3"
  role   = aws_iam_role.task.name
  policy = data.aws_iam_policy_document.task_s3.json
}

# Lambda roles trust lambda.amazonaws.com, so they need their own trust document.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Dispatcher role: starts one ECS task per run. Separate from the notifier so
# that the function allowed to start tasks is not the function allowed to send
# mail, and neither carries the app's S3 permissions.
resource "aws_iam_role" "dispatcher" {
  name               = "${local.name_prefix}-dispatcher"
  description        = "Dispatcher Lambda: start one ECS task per run."
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}


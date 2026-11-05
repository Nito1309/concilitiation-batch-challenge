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


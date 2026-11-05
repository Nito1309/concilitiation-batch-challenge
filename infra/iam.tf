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


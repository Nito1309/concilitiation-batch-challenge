# The stack's contract with whatever uses it. Four values: where to put files,
# what cluster runs them, which revision to run, and which function to point a
# trigger at. Everything else here is a convenience for the local loop.

output "bucket_name" {
  description = "Data bucket: inbox/ feeds the process, reports/ holds the output."
  value       = aws_s3_bucket.data.id
}

output "cluster_name" {
  description = "Cluster the dispatcher calls RunTask on."
  value       = aws_ecs_cluster.app.name
}

output "task_definition_arn" {
  description = "Revision to start, pinned by ARN so :latest cannot drift under it."
  value       = aws_ecs_task_definition.app.arn
}

output "dispatcher_name" {
  description = "Function the daily schedule invokes."
  value       = aws_lambda_function.dispatcher.function_name
}

output "notifier_name" {
  description = "Function the task-stopped rule invokes."
  value       = aws_lambda_function.notifier.function_name
}

# Local-loop outputs. They describe the stack's own plumbing rather than what a
# caller needs to use it, so they sit below the contract rather than in it.

output "repository_url" {
  description = "Registry URL the CI pushes to and ecs.tf pulls from."
  value       = aws_ecr_repository.app.repository_url
}

output "task_security_group_id" {
  description = "Security group every RunTask call must attach (with var.subnet_ids)."
  value       = aws_security_group.task.id
}

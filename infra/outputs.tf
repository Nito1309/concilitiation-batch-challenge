# One file for everything the stack hands out. These already existed, scattered
# across the files that create them; moving them here is the first half.

output "cluster_name" {
  description = "Cluster the dispatcher Lambda calls RunTask on (3.6)."
  value       = aws_ecs_cluster.app.name
}

output "task_definition_arn" {
  description = "Task definition family:revision to start, or to override per run."
  value       = aws_ecs_task_definition.app.arn
}

output "task_security_group_id" {
  description = "Security group every RunTask call must attach (with var.subnet_ids)."
  value       = aws_security_group.task.id
}

output "repository_url" {
  description = "Registry URL the CI pushes to and ecs.tf pulls from."
  value       = aws_ecr_repository.app.repository_url
}

output "s3_bucket_name" {
  description = "Real name of the data bucket, after any derivation."
  value       = aws_s3_bucket.data.id
}

output "dispatcher_function_name" {
  description = "Schedule target for 3.7 (its invoke permission is already pinned to it)."
  value       = aws_lambda_function.dispatcher.function_name
}

output "notifier_function_name" {
  description = "Function S3 calls for every object under inbox/."
  value       = aws_lambda_function.notifier.function_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "IDs of the private subnets (internet egress through NAT)."
  value       = aws_subnet.private[*].id
}

output "db_endpoint" {
  description = "PostgreSQL endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "db_secret_arn" {
  description = "ARN of the secret holding the database credentials."
  value       = aws_secretsmanager_secret.db.arn
}

output "db_security_group_id" {
  description = "ID of the database security group."
  value       = aws_security_group.db.id
}

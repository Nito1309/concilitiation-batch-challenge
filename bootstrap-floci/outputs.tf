output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "IDs de las subnets privadas (salida a internet por NAT)."
  value       = aws_subnet.private[*].id
}

output "db_endpoint" {
  description = "Endpoint de PostgreSQL (host:puerto)."
  value       = aws_db_instance.this.endpoint
}

output "db_secret_arn" {
  description = "ARN del secreto con las credenciales de la base de datos."
  value       = aws_secretsmanager_secret.db.arn
}

output "db_security_group_id" {
  description = "ID del security group de la base de datos."
  value       = aws_security_group.db.id
}

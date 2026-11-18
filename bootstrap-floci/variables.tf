variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for the resource names."
  type        = string
  default     = "conciliacion-batch"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "db_name" {
  description = "Database name."
  type        = string
  default     = "conciliacion"
}

variable "db_username" {
  description = "Database administrator user."
  type        = string
  default     = "conciliacion_admin"
}

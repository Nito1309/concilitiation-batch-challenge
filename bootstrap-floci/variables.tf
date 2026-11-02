variable "region" {
  description = "Región de AWS."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefijo para los nombres de los recursos."
  type        = string
  default     = "conciliacion-batch"
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "db_name" {
  description = "Nombre de la base de datos."
  type        = string
  default     = "conciliacion"
}

variable "db_username" {
  description = "Usuario administrador de la base de datos."
  type        = string
  default     = "conciliacion_admin"
}

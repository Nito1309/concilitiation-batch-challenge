variable "aws_region" {
  description = "Region for every resource in this stack."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project slug used in resource names."
  type        = string
  default     = "conciliacion-batch"
}

variable "environment" {
  description = "Deployment environment (lab / staging / prod)."
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["lab", "staging", "prod"], var.environment)
    error_message = "environment must be one of: lab, staging, prod."
  }
}

variable "bucket_name" {
  // TODO: Issue 3.2 for more info see:
  // https://github.com/Nito1309/conciliacion-batch-challenge/issues/3
  description = "Optional bucket name if empty, Github issue 3.2 derives it."
  type        = string
  default     = ""
}

variable "notification_email_from" {
  description = "Verified SES sender identity (SES is wired in 3.8)."
  type        = string
  nullable    = false
}


# --- from bootstrap-floci: no defaults on purpose ---
variable "vpc_id" {
  description = "VPC created by bootstrap-floci."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet ids created by bootstrap-floci."
  type        = list(string)
}

variable "db_security_group_id" {
  description = "Security group attached to the RDS instance."
  type        = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN holding the DB credentials JSON."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", var.db_secret_arn))
    error_message = "db_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "db_endpoint" {
  description = "RDS endpoint as host:port, straight from bootstrap-floci output."
  type        = string

  validation {
    condition     = can(regex("^[^:]+:[0-9]+$", var.db_endpoint))
    error_message = <<-EOT
      db_endpoint must be host:port from the bootstrap-floci output;
      if you copied terraform.tfvars.example, replace the placeholder.
    EOT
  }
}

variable "tags" {
  description = "Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}

# --- ECS task sizing (3.5) ---

variable "task_cpu" {
  description = "Fargate cpu units for the batch task: 512 = 0.5 vCPU."
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Fargate memory in MiB; must be a valid pair with task_cpu."
  type        = string
  default     = "1024"
}

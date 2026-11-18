# bootstrap-floci

Creates, on Floci, the resources that **already exist on AWS** and that your solution receives as variables:

- VPC with private subnets (internet egress through NAT).
- PostgreSQL database.
- Secret in Secrets Manager with the database credentials.
- Database security group.

It is only used in your local environment. It is not part of your solution and you do not need to modify it.

## Requirements

- Docker and Docker Compose
- Terraform 1.16.x
- AWS CLI v2
- jq (optional, to read the secret)

Terraform and the AWS CLI also ship in the `.docker/` container (see the main README). Inside the container, Floci is at `http://floci:4566`, not on `localhost`.

## Usage

From the repository root:

```bash
# 1. Start Floci
docker compose up -d

# 2. Point Terraform and the AWS CLI at Floci (Floci accepts any credentials)
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=us-east-1

# 3. Create the resources
cd bootstrap-floci
terraform init
terraform apply

# 4. Read the identifiers
terraform output
```

The database takes about a minute and a half to be created.

## Outputs

| Output | Description |
|---|---|
| `vpc_id` | ID of the VPC |
| `subnet_ids` | IDs of the private subnets |
| `db_endpoint` | PostgreSQL endpoint (`host:port`) |
| `db_secret_arn` | ARN of the secret holding the database credentials |
| `db_security_group_id` | ID of the database security group |

The secret is a JSON document with this shape:

```json
{
  "engine": "postgres",
  "host": "floci",
  "port": 7001,
  "dbname": "conciliacion",
  "username": "conciliacion_admin",
  "password": "..."
}
```

## Connecting to the database

The host `floci` resolves inside the `conciliacion-batch` Docker network, which is where Floci runs its containers (ECS tasks, Lambdas). From your machine use `localhost:7001`:

```bash
PGPASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id conciliacion-batch/db-credentials \
  --query SecretString --output text | jq -r .password) \
psql -h localhost -p 7001 -U conciliacion_admin -d conciliacion
```

## Destroying

```bash
terraform destroy
docker compose down
```

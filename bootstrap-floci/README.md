# bootstrap-floci

Crea en Floci los recursos que **en AWS ya existen** y que tu solución recibe como variables:

- VPC con subnets privadas (salida a internet por NAT).
- Base de datos PostgreSQL.
- Secreto en Secrets Manager con las credenciales de la base de datos.
- Security group de la base de datos.

Solo se usa en tu entorno local. No forma parte de tu solución ni necesitas modificarlo.

## Requisitos

- Docker y Docker Compose
- Terraform 1.16.x
- AWS CLI v2
- jq (opcional, para leer el secreto)

Terraform y la AWS CLI también vienen en el contenedor de `.docker/` (ver el README principal). Dentro del contenedor, Floci está en `http://floci:4566`, no en `localhost`.

## Uso

Desde la raíz del repositorio:

```bash
# 1. Levantar Floci
docker compose up -d

# 2. Apuntar Terraform y la AWS CLI a Floci (Floci acepta cualquier credencial)
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=us-east-1

# 3. Crear los recursos
cd bootstrap-floci
terraform init
terraform apply

# 4. Consultar los identificadores
terraform output
```

La base de datos tarda alrededor de un minuto y medio en crearse.

## Outputs

| Output | Descripción |
|---|---|
| `vpc_id` | ID de la VPC |
| `subnet_ids` | IDs de las subnets privadas |
| `db_endpoint` | Endpoint de PostgreSQL (`host:puerto`) |
| `db_secret_arn` | ARN del secreto con las credenciales de la base de datos |
| `db_security_group_id` | ID del security group de la base de datos |

El secreto es un JSON con este formato:

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

## Conectarse a la base de datos

El host `floci` se resuelve dentro de la red Docker `conciliacion-batch`, que es donde Floci corre los contenedores (tareas de ECS, Lambdas). Desde tu máquina usa `localhost:7001`:

```bash
PGPASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id conciliacion-batch/db-credentials \
  --query SecretString --output text | jq -r .password) \
psql -h localhost -p 7001 -U conciliacion_admin -d conciliacion
```

## Destruir

```bash
terraform destroy
docker compose down
```

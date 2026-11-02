# app: job batch `conciliacion-batch`

Job que **arranca, hace su trabajo y termina**. No es un servidor: no expone puertos.

El proveedor de pagos está simulado (las transacciones se generan a partir de la fecha), así que no necesitas credenciales reales.

## Modos de ejecución

| `RUN_MODE` | Qué hace |
|---|---|
| `daily` | Concilia el día anterior: compara las transacciones del proveedor contra los movimientos internos y genera un reporte. |
| `on_demand` | Igual que `daily`, pero para el rango de fechas indicado en `PAYLOAD`. |
| `feed` | Lee un archivo CSV de movimientos desde S3 (`INPUT_KEY`), lo valida y carga los movimientos a la base de datos. No genera reporte. |

## Variables de entorno

| Variable | Modos | Descripción |
|---|---|---|
| `RUN_MODE` | todos | `daily`, `on_demand` o `feed` |
| `BUCKET_NAME` | todos | Bucket donde la app lee y escribe |
| `DB_HOST` | todos | Host de PostgreSQL |
| `DB_PORT` | todos | Puerto de PostgreSQL (opcional, por defecto `5432`) |
| `DB_NAME` | todos | Nombre de la base de datos |
| `DB_USER` | todos | Usuario de la base de datos |
| `DB_PASSWORD` | todos | Contraseña de la base de datos |
| `PROVIDER_API_KEY` | `daily`, `on_demand` | API key del proveedor. La app solo valida que exista |
| `PAYLOAD` | `on_demand` | JSON opcional con el rango a conciliar (máximo 31 días). Si no se envía, se concilia el día anterior |
| `INPUT_KEY` | `feed` | Key del archivo CSV dentro del bucket |

Los datos de conexión a la base de datos están en el secreto de credenciales que ya existe (`host`, `port`, `dbname`, `username`, `password`).

La app usa el SDK de AWS para Python (boto3), así que toma credenciales y región de la cadena estándar del SDK.

Ejemplo de `PAYLOAD` (también en `ejemplos/payload.json`):

```json
{"fecha_inicio": "2026-10-20", "fecha_fin": "2026-10-20"}
```

## Formato del archivo de feed

CSV en UTF-8 con este encabezado exacto:

```csv
referencia,fecha,monto,moneda
TX-20261020-0001,2026-10-20,1249.98,MXN
```

Ejemplo completo en `ejemplos/feed-2026-10-20.csv`. Sus movimientos son del 2026-10-20, así que una ejecución `on_demand` sobre esa fecha muestra conciliadas, diferencias de monto y faltantes.

## Qué escribe

En S3 (`<rango>` es `fecha_inicio_fecha_fin`):

| Prefijo | `daily` / `on_demand` | `feed` |
|---|---|---|
| `raw/` | `raw/proveedor/<rango>/<run_id>.json`: respuesta del proveedor | `raw/feed/<fecha>/<run_id>-<archivo>`: copia del archivo original |
| `data/` | `data/conciliaciones/<rango>/<run_id>.json`: resultado por transacción | `data/movimientos/<fecha>/<run_id>.json`: movimientos normalizados |
| `reports/` | `reports/<rango>/<run_id>.json`: reporte de conciliación | — |
| `logs/` | `logs/<modo>/<fecha>/<run_id>.json`: resumen de la ejecución | igual |

En PostgreSQL (las tablas se crean si no existen):

- `conciliaciones`: una fila por cada conciliación (`daily` / `on_demand`).
- `movimientos`: una fila por cada movimiento cargado por `feed`.

## Logs y códigos de salida

Escribe logs en JSON, una línea por evento, a stdout.

| Código | Significado |
|---|---|
| `0` | Ejecución correcta |
| `1` | Error inesperado |
| `2` | Configuración inválida (falta una variable o tiene un valor no permitido) |
| `3` | Entrada inválida (`PAYLOAD` o archivo de feed) |
| `4` | Falla de una dependencia (S3, base de datos o proveedor) |

## Ejecutarla localmente contra Floci

Requiere Floci levantado y `bootstrap-floci/` aplicado (ver el README de la raíz).

```bash
docker build -t conciliacion-batch:local app/

docker run --rm --network conciliacion-batch \
  -e AWS_ENDPOINT_URL=http://floci:4566 \
  -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_REGION=us-east-1 \
  -e RUN_MODE=on_demand \
  -e PAYLOAD='{"fecha_inicio": "2026-10-20", "fecha_fin": "2026-10-20"}' \
  -e BUCKET_NAME=<tu-bucket> \
  -e DB_HOST=floci -e DB_PORT=7001 -e DB_NAME=conciliacion \
  -e DB_USER=conciliacion_admin -e DB_PASSWORD=<password-del-secreto> \
  -e PROVIDER_API_KEY=cualquier-valor \
  conciliacion-batch:local
```

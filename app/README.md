# app: `conciliacion-batch` batch job

A job that **starts, does its work and exits**. It is not a server: it exposes no ports.

The payment provider is simulated (transactions are generated from the date), so you do not need real credentials.

## Run modes

| `RUN_MODE` | What it does |
|---|---|
| `daily` | Reconciles the previous day: compares the provider's transactions against the internal movements and produces a report. |
| `on_demand` | Same as `daily`, but for the date range given in `PAYLOAD`. |
| `feed` | Reads a CSV file of movements from S3 (`INPUT_KEY`), validates it and loads the movements into the database. Produces no report. |

## Environment variables

| Variable | Modes | Description |
|---|---|---|
| `RUN_MODE` | all | `daily`, `on_demand` or `feed` |
| `BUCKET_NAME` | all | Bucket the app reads from and writes to |
| `DB_HOST` | all | PostgreSQL host |
| `DB_PORT` | all | PostgreSQL port (optional, defaults to `5432`) |
| `DB_NAME` | all | Database name |
| `DB_USER` | all | Database user |
| `DB_PASSWORD` | all | Database password |
| `PROVIDER_API_KEY` | `daily`, `on_demand` | Provider API key. The app only checks that it is present |
| `PAYLOAD` | `on_demand` | Optional JSON with the range to reconcile (31 days maximum). If omitted, the previous day is reconciled |
| `INPUT_KEY` | `feed` | Key of the CSV file inside the bucket |

The database connection data lives in the credentials secret that already exists (`host`, `port`, `dbname`, `username`, `password`).

The app uses the AWS SDK for Python (boto3), so it takes credentials and region from the standard SDK chain.

Example `PAYLOAD` (also in `ejemplos/payload.json`):

```json
{"fecha_inicio": "2026-10-20", "fecha_fin": "2026-10-20"}
```

The payload keys `fecha_inicio` / `fecha_fin` are part of the application contract and keep their Spanish names.

## Feed file format

CSV in UTF-8 with this exact header:

```csv
referencia,fecha,monto,moneda
TX-20261020-0001,2026-10-20,1249.98,MXN
```

The header is the contract between operations and the application: it is expected literally as written, so it is not translated.

A full example is in `ejemplos/feed-2026-10-20.csv`. Its movements are dated 2026-10-20, so an `on_demand` run over that date shows reconciled rows, amount differences and missing entries.

## What it writes

To S3 (`<rango>` is `fecha_inicio_fecha_fin`, and keeps its Spanish name because it is part of the object key layout):

| Prefix | `daily` / `on_demand` | `feed` |
|---|---|---|
| `raw/` | `raw/proveedor/<rango>/<run_id>.json`: provider response | `raw/feed/<fecha>/<run_id>-<archivo>`: copy of the original file |
| `data/` | `data/conciliaciones/<rango>/<run_id>.json`: per-transaction result | `data/movimientos/<fecha>/<run_id>.json`: normalised movements |
| `reports/` | `reports/<rango>/<run_id>.json`: reconciliation report | — |
| `logs/` | `logs/<modo>/<fecha>/<run_id>.json`: run summary | same |

To PostgreSQL (tables are created if they do not exist):

- `conciliaciones`: one row per reconciliation (`daily` / `on_demand`).
- `movimientos`: one row per movement loaded by `feed`.

## Logs and exit codes

It writes JSON logs, one line per event, to stdout.

| Code | Meaning |
|---|---|
| `0` | Successful run |
| `1` | Unexpected error |
| `2` | Invalid configuration (a variable is missing or has a disallowed value) |
| `3` | Invalid input (`PAYLOAD` or feed file) |
| `4` | Dependency failure (S3, database or provider) |

## Running it locally against Floci

Requires Floci running and `bootstrap-floci/` applied (see the README at the repository root).

```bash
docker build -t conciliacion-batch:local app/

docker run --rm --network conciliacion-batch \
  -e AWS_ENDPOINT_URL=http://floci:4566 \
  -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_REGION=us-east-1 \
  -e RUN_MODE=on_demand \
  -e PAYLOAD='{"fecha_inicio": "2026-10-20", "fecha_fin": "2026-10-20"}' \
  -e BUCKET_NAME=<your-bucket> \
  -e DB_HOST=floci -e DB_PORT=7001 -e DB_NAME=conciliacion \
  -e DB_USER=conciliacion_admin -e DB_PASSWORD=<password-from-the-secret> \
  -e PROVIDER_API_KEY=any-value \
  conciliacion-batch:local
```

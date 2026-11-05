"""Dispatcher: punto de entrada de las tres formas de ejecutar el batch.

Una sola función atiende los tres disparadores porque el trabajo es el mismo:
traducir lo que llegó a los parámetros que la tarea necesita.

    Scheduler  -> RUN_MODE=daily
    AWS CLI    -> RUN_MODE=on_demand + PAYLOAD
    inbox/     -> RUN_MODE=feed + INPUT_KEY

Los eventos no se distinguen por un flag de configuración sino por su forma, así
que añadir un disparador no obliga a tocar los otros dos.

`RunTask` todavía no se llama (Piece 4): lo que esta pieza prueba es que cada
disparador llega aquí con sus datos. La respuesta lo dice en `procesado`.
"""

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _traducir(event):
    """Devuelve (RUN_MODE, variables de la tarea) para el evento recibido.

    S3 manda `Records` con `s3`, Scheduler manda `source: aws.scheduler`, y la
    CLI manda el payload del usuario tal cual.
    """
    if isinstance(event, dict) and event.get("Records"):
        s3 = event["Records"][0].get("s3")
        if s3:
            return "feed", {"INPUT_KEY": s3["object"]["key"]}

    if isinstance(event, dict) and event.get("source") == "aws.scheduler":
        return "daily", {}

    # PAYLOAD viaja como string JSON: RunTask solo acepta strings en
    # `environmentOverrides`, y así el mismo valor sirve en los dos caminos.
    if isinstance(event, dict) and event:
        return "on_demand", {"PAYLOAD": json.dumps(event)}

    # Sin payload, `on_demand` concilia el día anterior: es el
    # comportamiento por defecto del contenedor, no una decisión de aquí.
    return "on_demand", {}


def handler(event, context):
    modo, variables = _traducir(event)
    logger.info("RUN_MODE=%s variables=%s", modo, json.dumps(variables, default=str))
    logger.info(
        "Destino: cluster=%s task_definition=%s subnets=%s security_groups=%s",
        os.environ.get("CLUSTER_NAME"),
        os.environ.get("TASK_DEFINITION"),
        os.environ.get("SUBNETS"),
        os.environ.get("SECURITY_GROUPS"),
    )

    return {
        "ok": True,
        "run_mode": modo,
        "variables": variables,
        "procesado": False,
        "motivo": "RunTask es Piece 4",
    }

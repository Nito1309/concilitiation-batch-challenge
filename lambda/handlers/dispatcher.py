"""Dispatcher: punto de entrada de cada ejecución programada.

Esta Lambda es un traductor fino: recibe el evento del scheduler, lo deja en el
log y arranca (en Piece 4) una tarea de ECS con `RunTask`. Nada de lógica de
negocio aquí: lo que el contenedor no pueda reutilizar no va en la Lambda.
"""

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """Registra el evento y confirma que el entorno trae el destino.

    La respuesta es solo para que la invocación de prueba muestre algo útil:
    esta Lambda todavía no llama a ECS.
    """
    logger.info("Evento recibido: %s", json.dumps(event, default=str))
    logger.info(
        "Destino: cluster=%s task_definition=%s subnets=%s security_groups=%s",
        os.environ.get("CLUSTER_NAME"),
        os.environ.get("TASK_DEFINITION"),
        os.environ.get("SUBNETS"),
        os.environ.get("SECURITY_GROUPS"),
    )

    return {"ok": True, "procesado": False, "motivo": "stub de 3.6"}

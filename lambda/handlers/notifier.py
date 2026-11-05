"""Notifier: punto de entrada de cada objeto nuevo en el bucket.

S3 invoca esta función cuando aparece un objeto bajo `inbox/`. En Piece 4
traducirá ese evento en un correo con SES; aquí solo deja constancia de qué
llegó, para poder revisar el disparo sin enviar nada.
"""

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """Registra el evento de S3 y confirma que el destino del correo existe."""
    logger.info("Evento recibido: %s", json.dumps(event, default=str))
    logger.info(
        "Correo: de=%s para=%s",
        os.environ.get("SES_SENDER"),
        os.environ.get("SES_RECIPIENT"),
    )

    return {"ok": True, "enviado": False, "motivo": "stub de 3.6"}

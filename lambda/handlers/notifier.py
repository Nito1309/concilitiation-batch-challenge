"""Notifier: email with the result of a batch run.

EventBridge invokes this function when a task in the cluster reaches `STOPPED`.
The event is the ECS state change, and it carries the three pieces that say what
happened: `stopCode` (why ECS stopped it), `stoppedReason` (the detail ECS
wrote) and the container's `exitCode` (what the application decided).

They are read in that order because that is the order of the investigation: the
exit code says whether there is anything to look at, the stop reason says whether
it was the container or the infrastructure, and the logs hold the detail.
"""

import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Table from app/README.md. The container already decided what happened; here it
# is only turned into something readable without opening the code.
SALIDAS = {
    0: "ejecución correcta",
    1: "error inesperado",
    2: "configuración inválida (falta una variable o tiene un valor no permitido)",
    3: "entrada inválida (PAYLOAD o archivo de feed)",
    4: "falla de una dependencia (S3, base de datos o proveedor)",
}

# The task names its log group with its own id, so the email can link to the
# logs without anyone having to search for them.
LOG_GROUP = os.environ.get("LOG_GROUP_NAME")
BUCKET = os.environ.get("BUCKET_NAME")


def handler(event, context):
    """Builds the email from the state change and sends it through SES."""
    if event.get("detail-type") != "ECS Task State Change":
        # Not every trigger is a result: a new object in inbox/ is work to do,
        # not news to report.
        logger.info("Evento ignorado: detail-type=%s", event.get("detail-type"))
        return {"ok": True, "enviado": False, "motivo": "no es un cambio de estado de ECS"}

    detail = event.get("detail", {})
    contenedores = detail.get("containers") or []
    codigos = [c["exitCode"] for c in contenedores if "exitCode" in c]
    codigo = codigos[0] if codigos else None

    asunto = _asunto(codigo)
    cuerpo = _cuerpo(detail, contenedores, codigo)

    logger.info("Aviso: %s", asunto)
    respuesta = boto3.client("ses").send_email(
        Source=os.environ["SES_SENDER"],
        Destination={"ToAddresses": [os.environ["SES_RECIPIENT"]]},
        Message={
            "Subject": {"Data": asunto, "Charset": "UTF-8"},
            "Body": {"Text": {"Data": cuerpo, "Charset": "UTF-8"}},
        },
    )
    logger.info("Enviado: message_id=%s", respuesta.get("MessageId"))
    return {"ok": True, "enviado": True, "exit_code": codigo}


def _asunto(codigo):
    """One line that already says whether the email needs opening today."""
    if codigo is None:
        return "[conciliación] SIN EJECUTAR · la tarea no arrancó"
    if codigo == 0:
        return "[conciliación] OK · ejecución correcta"
    return f"[conciliación] FALLA · salida {codigo}"


def _cuerpo(detail, contenedores, codigo):
    """Plain text: it reads on a phone and does not depend on a mail client."""
    lineas = [
        f"Tarea:      {detail.get('taskArn', '?')}",
        f"Clúster:    {detail.get('clusterArn', '?')}",
        f"Detenida:   {detail.get('stopCode', '?')}",
        f"Razón:      {detail.get('stoppedReason', '?')}",
        f"Salida:     {_salida(codigo)}",
    ]

    for contenedor in contenedores:
        if "exitCode" in contenedor:
            lineas.append(
                f"Contenedor: {contenedor.get('name', '?')} = {contenedor['exitCode']}"
            )

    if codigo != 0:
        lineas += [
            "",
            "Qué revisar, en este orden:",
            f"  1. Los logs de la tarea: {_logs(detail)}",
            "  2. Las variables del task definition y el secreto del proveedor.",
            f"  3. La entrada, si la salida fue 3 (bucket {BUCKET or '<bucket>'});",
            "     si fue 4, la dependencia que falló (S3, base de datos, proveedor).",
        ]

    return "\n".join(lineas)


def _salida(codigo):
    if codigo is None:
        return "sin código de salida: la tarea se detuvo antes de arrancar"
    return f"{codigo} ({SALIDAS.get(codigo, 'código no documentado')})"


def _logs(detail):
    """The task stream is named after its id; that is enough to reach it."""
    corto = detail.get("taskArn", "").rsplit("/", 1)[-1] or "?"
    return f"{LOG_GROUP or '/ecs/<cluster>-app'} · stream app/{corto}"

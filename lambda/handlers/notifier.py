"""Notifier: correo con el resultado de una ejecución del batch.

EventBridge invoca esta función cuando una tarea del clúster llega a `STOPPED`.
El evento es el cambio de estado de ECS, y ahí están las tres piezas que dicen
qué pasó: `stopCode` (por qué la detuvo ECS), `stoppedReason` (el detalle que
escribió ECS) y el `exitCode` del contenedor (lo que decidió la aplicación).

Se leen en ese orden porque es el orden de la investigación: el código de salida
dice si hay algo que mirar, la razón del stop dice si fue el contenedor o la
infraestructura, y los logs ya son el detalle.
"""

import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Tabla de app/README.md. El contenedor ya decidió qué pasó; aquí sólo se
# traduce a algo que se entienda sin abrir el código.
SALIDAS = {
    0: "ejecución correcta",
    1: "error inesperado",
    2: "configuración inválida (falta una variable o tiene un valor no permitido)",
    3: "entrada inválida (PAYLOAD o archivo de feed)",
    4: "falla de una dependencia (S3, base de datos o proveedor)",
}

# La tarea nombra su log group con su propio id, así que el correo puede llevar
# a los logs sin que nadie tenga que buscarlos.
LOG_GROUP = os.environ.get("LOG_GROUP_NAME")
BUCKET = os.environ.get("BUCKET_NAME")


def handler(event, context):
    """Arma el correo a partir del cambio de estado y lo manda por SES."""
    if event.get("detail-type") != "ECS Task State Change":
        # No todo disparo es un resultado: un objeto nuevo en inbox/ es trabajo
        # por hacer, no una noticia que dar.
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
    """Una línea que ya dice si hay que abrir el correo hoy."""
    if codigo is None:
        return "[conciliación] SIN EJECUTAR · la tarea no arrancó"
    if codigo == 0:
        return "[conciliación] OK · ejecución correcta"
    return f"[conciliación] FALLA · salida {codigo}"


def _cuerpo(detail, contenedores, codigo):
    """Texto plano: se lee en el móvil y no depende de un cliente de correo."""
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
    """El stream de la tarea se llama como su id; con eso basta para llegar."""
    corto = detail.get("taskArn", "").rsplit("/", 1)[-1] or "?"
    return f"{LOG_GROUP or '/ecs/<cluster>-app'} · stream app/{corto}"

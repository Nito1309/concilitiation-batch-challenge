"""Lectura y validación de la configuración desde variables de entorno."""

import json
import os
from dataclasses import dataclass
from datetime import date, timedelta

from .errores import ErrorConfiguracion, ErrorEntrada

MODOS = ("daily", "on_demand", "feed")


@dataclass(frozen=True)
class Config:
    modo: str
    bucket: str
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    provider_api_key: str | None
    fecha_inicio: date | None
    fecha_fin: date | None
    input_key: str | None


def _requerida(nombre: str) -> str:
    valor = os.environ.get(nombre, "").strip()
    if not valor:
        raise ErrorConfiguracion(f"Falta la variable de entorno requerida {nombre}")
    return valor


def _leer_fecha(payload: dict, campo: str) -> date:
    valor = payload.get(campo)
    if valor is None:
        raise ErrorEntrada(f"PAYLOAD no incluye el campo '{campo}'")
    try:
        return date.fromisoformat(valor)
    except (TypeError, ValueError):
        raise ErrorEntrada(f"PAYLOAD.{campo} no es una fecha válida (AAAA-MM-DD): {valor!r}")


def _rango_de_fechas(modo: str) -> tuple[date, date]:
    ayer = date.today() - timedelta(days=1)
    payload_crudo = os.environ.get("PAYLOAD", "").strip()

    if modo == "daily" or not payload_crudo:
        return ayer, ayer

    try:
        payload = json.loads(payload_crudo)
    except json.JSONDecodeError as e:
        raise ErrorEntrada(f"PAYLOAD no es un JSON válido: {e}")
    if not isinstance(payload, dict):
        raise ErrorEntrada("PAYLOAD debe ser un objeto JSON")

    inicio = _leer_fecha(payload, "fecha_inicio")
    fin = _leer_fecha(payload, "fecha_fin")
    if inicio > fin:
        raise ErrorEntrada(f"PAYLOAD.fecha_inicio ({inicio}) es posterior a fecha_fin ({fin})")
    if (fin - inicio).days > 31:
        raise ErrorEntrada("El rango de fechas no puede ser mayor a 31 días")
    return inicio, fin


def cargar() -> Config:
    modo = _requerida("RUN_MODE")
    if modo not in MODOS:
        raise ErrorConfiguracion(f"RUN_MODE inválido: {modo!r}. Valores permitidos: {', '.join(MODOS)}")

    bucket = _requerida("BUCKET_NAME")
    db_host = _requerida("DB_HOST")
    db_name = _requerida("DB_NAME")
    db_user = _requerida("DB_USER")
    db_password = _requerida("DB_PASSWORD")

    db_port_crudo = os.environ.get("DB_PORT", "5432").strip()
    if not db_port_crudo.isdigit():
        raise ErrorConfiguracion(f"DB_PORT no es un número: {db_port_crudo!r}")

    provider_api_key = None
    fecha_inicio = fecha_fin = None
    input_key = None

    if modo == "feed":
        input_key = _requerida("INPUT_KEY")
    else:
        provider_api_key = _requerida("PROVIDER_API_KEY")
        fecha_inicio, fecha_fin = _rango_de_fechas(modo)

    return Config(
        modo=modo,
        bucket=bucket,
        db_host=db_host,
        db_port=int(db_port_crudo),
        db_name=db_name,
        db_user=db_user,
        db_password=db_password,
        provider_api_key=provider_api_key,
        fecha_inicio=fecha_inicio,
        fecha_fin=fecha_fin,
        input_key=input_key,
    )

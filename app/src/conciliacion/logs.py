"""Logs estructurados en JSON, una línea por evento, a stdout."""

import json
import sys
from datetime import datetime, timezone

_contexto: dict = {}


def configurar(**campos) -> None:
    _contexto.update(campos)


def _emitir(nivel: str, mensaje: str, **campos) -> None:
    evento = {
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "level": nivel,
        "message": mensaje,
        **_contexto,
        **campos,
    }
    print(json.dumps(evento, ensure_ascii=False, default=str), file=sys.stdout, flush=True)


def info(mensaje: str, **campos) -> None:
    _emitir("INFO", mensaje, **campos)


def error(mensaje: str, **campos) -> None:
    _emitir("ERROR", mensaje, **campos)

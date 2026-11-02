"""Lectura y validación de archivos de feed (CSV)."""

import csv
import io
from datetime import date
from decimal import Decimal, InvalidOperation

from .errores import ErrorEntrada

COLUMNAS = ("referencia", "fecha", "monto", "moneda")


def parsear(contenido: str, key: str) -> list[dict]:
    lector = csv.DictReader(io.StringIO(contenido))
    if tuple(lector.fieldnames or ()) != COLUMNAS:
        raise ErrorEntrada(
            f"{key}: encabezado inválido {lector.fieldnames}. Se esperaba: {','.join(COLUMNAS)}"
        )

    movimientos = []
    for numero, fila in enumerate(lector, start=2):
        try:
            referencia = fila["referencia"].strip()
            if not referencia:
                raise ValueError("referencia vacía")
            fecha = date.fromisoformat(fila["fecha"].strip())
            monto = Decimal(fila["monto"].strip())
            moneda = fila["moneda"].strip().upper()
            if len(moneda) != 3:
                raise ValueError(f"moneda inválida {moneda!r}")
        except (AttributeError, ValueError, InvalidOperation) as e:
            raise ErrorEntrada(f"{key}, línea {numero}: {e}")

        movimientos.append(
            {"referencia": referencia, "fecha": fecha, "monto": monto, "moneda": moneda}
        )

    if not movimientos:
        raise ErrorEntrada(f"{key}: el archivo no contiene movimientos")
    return movimientos

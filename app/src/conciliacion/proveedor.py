"""Simulated payment provider client.

There is no real provider: transactions are generated deterministically from the
date, so two runs over the same day return the same data.
"""

import random
import time
from datetime import date, timedelta
from decimal import Decimal

TRANSACCIONES_POR_DIA = 25


def _dias(inicio: date, fin: date):
    dia = inicio
    while dia <= fin:
        yield dia
        dia += timedelta(days=1)


def consultar_transacciones(api_key: str, inicio: date, fin: date) -> list[dict]:
    time.sleep(1)

    transacciones = []
    for dia in _dias(inicio, fin):
        generador = random.Random(dia.toordinal())
        for i in range(1, TRANSACCIONES_POR_DIA + 1):
            centavos = generador.randint(1_000, 500_000)
            transacciones.append(
                {
                    "referencia": f"TX-{dia:%Y%m%d}-{i:04d}",
                    "fecha": dia.isoformat(),
                    "monto": f"{Decimal(centavos) / 100:.2f}",
                    "moneda": "MXN",
                }
            )
    return transacciones

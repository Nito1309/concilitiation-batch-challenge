"""Punto de entrada: ejecuta el modo indicado en RUN_MODE y devuelve el código de salida."""

import sys
import time
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import PurePosixPath

from . import config as configuracion
from . import feed, logs, proveedor
from .almacenamiento import Almacenamiento
from .base_datos import BaseDatos
from .errores import ErrorAplicacion


def conciliar(cfg, run_id: str, s3: Almacenamiento, db: BaseDatos) -> dict:
    rango = f"{cfg.fecha_inicio}_{cfg.fecha_fin}"
    logs.info("Consultando transacciones del proveedor", fecha_inicio=cfg.fecha_inicio, fecha_fin=cfg.fecha_fin)
    externas = proveedor.consultar_transacciones(cfg.provider_api_key, cfg.fecha_inicio, cfg.fecha_fin)
    raw_key = s3.escribir_json(f"raw/proveedor/{rango}/{run_id}.json", externas)

    internas = {m["referencia"]: m for m in db.movimientos_en_rango(cfg.fecha_inicio, cfg.fecha_fin)}
    resultado = []
    for tx in externas:
        interna = internas.pop(tx["referencia"], None)
        if interna is None:
            estado = "solo_proveedor"
        elif interna["monto"] == Decimal(tx["monto"]):
            estado = "conciliada"
        else:
            estado = "diferencia_monto"
        resultado.append({**tx, "monto_interno": interna and interna["monto"], "estado": estado})
    for interna in internas.values():
        resultado.append({**interna, "monto_interno": interna["monto"], "estado": "solo_interno"})

    data_key = s3.escribir_json(f"data/conciliaciones/{rango}/{run_id}.json", resultado)

    conciliadas = sum(1 for r in resultado if r["estado"] == "conciliada")
    resumen = {
        "run_id": run_id,
        "modo": cfg.modo,
        "fecha_inicio": cfg.fecha_inicio,
        "fecha_fin": cfg.fecha_fin,
        "total_proveedor": len(externas),
        "total_interno": sum(1 for r in resultado if r["monto_interno"] is not None),
        "conciliadas": conciliadas,
        "diferencias": len(resultado) - conciliadas,
    }
    reporte_key = s3.escribir_json(f"reports/{rango}/{run_id}.json", {**resumen, "detalle": resultado})
    db.insertar_conciliacion({**resumen, "reporte_key": reporte_key})

    return {**resumen, "archivos": [raw_key, data_key, reporte_key]}


def procesar_feed(cfg, run_id: str, s3: Almacenamiento, db: BaseDatos) -> dict:
    logs.info("Procesando archivo de feed", input_key=cfg.input_key)
    contenido = s3.leer_texto(cfg.input_key)
    movimientos = feed.parsear(contenido, cfg.input_key)

    hoy = date.today().isoformat()
    nombre = PurePosixPath(cfg.input_key).name
    raw_key = s3.escribir(f"raw/feed/{hoy}/{run_id}-{nombre}", contenido, "text/csv")
    data_key = s3.escribir_json(f"data/movimientos/{hoy}/{run_id}.json", movimientos)
    db.insertar_movimientos(run_id, cfg.input_key, movimientos)

    return {
        "run_id": run_id,
        "modo": cfg.modo,
        "input_key": cfg.input_key,
        "movimientos": len(movimientos),
        "archivos": [raw_key, data_key],
    }


def main() -> int:
    run_id = str(uuid.uuid4())
    inicio = time.monotonic()
    logs.configurar(run_id=run_id)
    logs.info("Inicio de la ejecución")

    try:
        cfg = configuracion.cargar()
        logs.configurar(modo=cfg.modo)

        s3 = Almacenamiento(cfg.bucket)
        with BaseDatos(cfg) as db:
            db.preparar_esquema()
            if cfg.modo == "feed":
                resumen = procesar_feed(cfg, run_id, s3, db)
            else:
                resumen = conciliar(cfg, run_id, s3, db)

        resumen["duracion_segundos"] = round(time.monotonic() - inicio, 2)
        resumen["finalizado_en"] = datetime.now(timezone.utc).isoformat()
        s3.escribir_json(f"logs/{cfg.modo}/{date.today().isoformat()}/{run_id}.json", resumen)
    except ErrorAplicacion as e:
        logs.error(str(e), tipo=type(e).__name__, codigo_salida=e.codigo_salida)
        return e.codigo_salida
    except Exception as e:
        logs.error(f"Error inesperado: {e!r}", tipo=type(e).__name__, codigo_salida=1)
        return 1

    logs.info("Ejecución terminada", **resumen)
    return 0


if __name__ == "__main__":
    sys.exit(main())

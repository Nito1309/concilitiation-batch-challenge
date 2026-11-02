"""Acceso a PostgreSQL."""

from datetime import date

import psycopg

from .config import Config
from .errores import ErrorDependencia

ESQUEMA = """
CREATE TABLE IF NOT EXISTS conciliaciones (
    id                  BIGSERIAL PRIMARY KEY,
    run_id              UUID NOT NULL,
    modo                TEXT NOT NULL,
    fecha_inicio        DATE NOT NULL,
    fecha_fin           DATE NOT NULL,
    total_proveedor     INTEGER NOT NULL,
    total_interno       INTEGER NOT NULL,
    conciliadas         INTEGER NOT NULL,
    diferencias         INTEGER NOT NULL,
    reporte_key         TEXT NOT NULL,
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS movimientos (
    id                  BIGSERIAL PRIMARY KEY,
    run_id              UUID NOT NULL,
    archivo             TEXT NOT NULL,
    referencia          TEXT NOT NULL,
    fecha               DATE NOT NULL,
    monto               NUMERIC(14, 2) NOT NULL,
    moneda              CHAR(3) NOT NULL,
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


class BaseDatos:
    def __init__(self, config: Config):
        try:
            self._conexion = psycopg.connect(
                host=config.db_host,
                port=config.db_port,
                dbname=config.db_name,
                user=config.db_user,
                password=config.db_password,
                connect_timeout=10,
            )
        except psycopg.Error as e:
            raise ErrorDependencia(
                f"No se pudo conectar a PostgreSQL en {config.db_host}:{config.db_port}: {e}"
            )

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self._conexion.close()

    def preparar_esquema(self) -> None:
        self._ejecutar(lambda cur: cur.execute(ESQUEMA))

    def insertar_movimientos(self, run_id: str, archivo: str, movimientos: list[dict]) -> None:
        filas = [
            (run_id, archivo, m["referencia"], m["fecha"], m["monto"], m["moneda"])
            for m in movimientos
        ]
        self._ejecutar(
            lambda cur: cur.executemany(
                "INSERT INTO movimientos (run_id, archivo, referencia, fecha, monto, moneda) "
                "VALUES (%s, %s, %s, %s, %s, %s)",
                filas,
            )
        )

    def movimientos_en_rango(self, inicio: date, fin: date) -> list[dict]:
        def consulta(cur):
            cur.execute(
                "SELECT referencia, fecha, monto, moneda FROM movimientos "
                "WHERE fecha BETWEEN %s AND %s",
                (inicio, fin),
            )
            return [
                {"referencia": r, "fecha": f, "monto": m, "moneda": mo}
                for r, f, m, mo in cur.fetchall()
            ]

        return self._ejecutar(consulta)

    def insertar_conciliacion(self, registro: dict) -> None:
        self._ejecutar(
            lambda cur: cur.execute(
                "INSERT INTO conciliaciones (run_id, modo, fecha_inicio, fecha_fin, "
                "total_proveedor, total_interno, conciliadas, diferencias, reporte_key) "
                "VALUES (%(run_id)s, %(modo)s, %(fecha_inicio)s, %(fecha_fin)s, "
                "%(total_proveedor)s, %(total_interno)s, %(conciliadas)s, %(diferencias)s, "
                "%(reporte_key)s)",
                registro,
            )
        )

    def _ejecutar(self, operacion):
        try:
            with self._conexion.transaction(), self._conexion.cursor() as cur:
                return operacion(cur)
        except psycopg.Error as e:
            raise ErrorDependencia(f"Error en PostgreSQL: {e}")

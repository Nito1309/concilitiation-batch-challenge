"""Errores de la aplicación. Cada tipo corresponde a un código de salida."""


class ErrorAplicacion(Exception):
    codigo_salida = 1


class ErrorConfiguracion(ErrorAplicacion):
    """Falta una variable de entorno o tiene un valor inválido."""

    codigo_salida = 2


class ErrorEntrada(ErrorAplicacion):
    """El payload o el archivo de entrada no son válidos."""

    codigo_salida = 3


class ErrorDependencia(ErrorAplicacion):
    """No se pudo usar S3, la base de datos o el proveedor."""

    codigo_salida = 4

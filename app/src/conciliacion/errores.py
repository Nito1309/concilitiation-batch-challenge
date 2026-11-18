"""Application errors. Each type maps to one exit code."""


class ErrorAplicacion(Exception):
    codigo_salida = 1


class ErrorConfiguracion(ErrorAplicacion):
    """An environment variable is missing or holds an invalid value."""

    codigo_salida = 2


class ErrorEntrada(ErrorAplicacion):
    """The payload or the input file is not valid."""

    codigo_salida = 3


class ErrorDependencia(ErrorAplicacion):
    """S3, the database or the provider could not be used."""

    codigo_salida = 4

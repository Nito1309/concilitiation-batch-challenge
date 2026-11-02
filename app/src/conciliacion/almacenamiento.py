"""Lectura y escritura de objetos en S3."""

import json

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from .errores import ErrorDependencia, ErrorEntrada


class Almacenamiento:
    def __init__(self, bucket: str):
        self.bucket = bucket
        self._s3 = boto3.client("s3")

    def leer_texto(self, key: str) -> str:
        try:
            respuesta = self._s3.get_object(Bucket=self.bucket, Key=key)
        except ClientError as e:
            codigo = e.response.get("Error", {}).get("Code")
            if codigo in ("NoSuchKey", "404"):
                raise ErrorEntrada(f"No existe el objeto s3://{self.bucket}/{key}")
            raise ErrorDependencia(f"No se pudo leer s3://{self.bucket}/{key}: {e}")
        except BotoCoreError as e:
            raise ErrorDependencia(f"No se pudo leer s3://{self.bucket}/{key}: {e}")

        cuerpo = respuesta["Body"].read()
        try:
            return cuerpo.decode("utf-8")
        except UnicodeDecodeError:
            raise ErrorEntrada(f"s3://{self.bucket}/{key} no es texto UTF-8")

    def escribir(self, key: str, contenido: str, content_type: str) -> str:
        try:
            self._s3.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=contenido.encode("utf-8"),
                ContentType=content_type,
            )
        except (BotoCoreError, ClientError) as e:
            raise ErrorDependencia(f"No se pudo escribir s3://{self.bucket}/{key}: {e}")
        return key

    def escribir_json(self, key: str, datos) -> str:
        contenido = json.dumps(datos, ensure_ascii=False, indent=2, default=str)
        return self.escribir(key, contenido, "application/json")

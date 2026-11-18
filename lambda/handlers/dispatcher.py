"""Dispatcher: entry point for the three ways of running the batch.

A single function serves all three triggers because the work is the same:
translate whatever arrived into the parameters the task needs.

    Scheduler  -> RUN_MODE=daily
    AWS CLI    -> RUN_MODE=on_demand + PAYLOAD
    inbox/     -> RUN_MODE=feed + INPUT_KEY

Events are told apart by their shape rather than by a configuration flag, so
adding a trigger does not force changes in the other two.

`RunTask` is not called yet (Piece 4): what this piece proves is that every
trigger reaches this point with its data. The response says so in `procesado`.
"""

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _traducir(event):
    """Returns (RUN_MODE, task environment variables) for the event received.

    S3 sends `Records` with `s3`, Scheduler sends `source: aws.scheduler`, and
    the CLI sends the user payload as is.
    """
    if isinstance(event, dict) and event.get("Records"):
        s3 = event["Records"][0].get("s3")
        if s3:
            return "feed", {"INPUT_KEY": s3["object"]["key"]}

    if isinstance(event, dict) and event.get("source") == "aws.scheduler":
        return "daily", {}

    # PAYLOAD travels as a JSON string: RunTask only accepts strings in
    # `environmentOverrides`, and this way the same value works on both paths.
    if isinstance(event, dict) and event:
        return "on_demand", {"PAYLOAD": json.dumps(event)}

    # Without a payload, `on_demand` reconciles the previous day: that is the
    # container's default behaviour, not a decision made here.
    return "on_demand", {}


def handler(event, context):
    modo, variables = _traducir(event)
    logger.info("RUN_MODE=%s variables=%s", modo, json.dumps(variables, default=str))
    logger.info(
        "Destino: cluster=%s task_definition=%s subnets=%s security_groups=%s",
        os.environ.get("CLUSTER_NAME"),
        os.environ.get("TASK_DEFINITION"),
        os.environ.get("SUBNETS"),
        os.environ.get("SECURITY_GROUPS"),
    )

    return {
        "ok": True,
        "run_mode": modo,
        "variables": variables,
        "procesado": False,
        "motivo": "RunTask es Piece 4",
    }

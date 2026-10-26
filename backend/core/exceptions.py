import logging

from django.core.exceptions import PermissionDenied, ValidationError as DjangoValidationError
from django.db import DatabaseError
from django.http import Http404
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import exception_handler

logger = logging.getLogger(__name__)


class Conflict(exceptions.APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "This action conflicts with the current state."
    default_code = "conflict"


class ServiceUnavailable(exceptions.APIException):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    default_detail = "This feature is not available yet."
    default_code = "service_unavailable"


def _message_from(data):
    """Pick a single human-readable message from DRF error data."""
    if isinstance(data, dict):
        if "detail" in data:
            return _message_from(data["detail"])
        for value in data.values():
            message = _message_from(value)
            if message:
                return message
    if isinstance(data, (list, tuple)) and data:
        return _message_from(data[0])
    if data:
        return str(data)
    return "Something went wrong."


def api_exception_handler(exc, context):
    """
    Consistent error envelope:
        {"error": {"code": "...", "message": "...", "fields": {...}}}
    Unexpected errors are logged and never leak internals to the client.
    """
    if isinstance(exc, DjangoValidationError):
        exc = exceptions.ValidationError(exc.message_dict if hasattr(exc, "message_dict") else exc.messages)
    elif isinstance(exc, Http404):
        exc = exceptions.NotFound()
    elif isinstance(exc, PermissionDenied):
        exc = exceptions.PermissionDenied()

    response = exception_handler(exc, context)
    if response is None:
        if isinstance(exc, DatabaseError):
            logger.exception("Database error while handling %s", context.get("view"))
        else:
            logger.exception("Unhandled API error in %s", context.get("view"))
        return Response(
            {"error": {"code": "server_error", "message": "Something went wrong. Please try again."}},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    data = response.data
    code = getattr(exc, "default_code", "error")
    if isinstance(exc, exceptions.APIException):
        codes = exc.get_codes()
        if isinstance(codes, str):
            code = codes
    body = {"code": code, "message": _message_from(data)}
    if isinstance(exc, exceptions.ValidationError) and isinstance(data, dict):
        body["code"] = "validation_error"
        body["fields"] = data
    response.data = {"error": body}
    return response

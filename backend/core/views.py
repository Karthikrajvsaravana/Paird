from django.db import connection
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView


@api_view(["GET"])
@permission_classes([AllowAny])
@throttle_classes([])
def health(request):
    """Liveness + database reachability. Reveals no configuration."""
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        database = "ok"
    except Exception:  # noqa: BLE001 - never leak driver errors
        database = "unavailable"
    status_code = 200 if database == "ok" else 503
    return Response({"status": "ok" if database == "ok" else "degraded", "database": database}, status=status_code)


def json_404(request, exception=None):
    from django.http import JsonResponse

    return JsonResponse({"error": {"code": "not_found", "message": "Not found."}}, status=404)


def json_500(request):
    from django.http import JsonResponse

    return JsonResponse({"error": {"code": "server_error", "message": "Something went wrong. Please try again."}}, status=500)


class CountryListView(APIView):
    """All countries, alphabetical: [{code, name, has_states}]."""

    def get(self, request):
        from .locations import countries

        return Response([{"code": c["code"], "name": c["name"], "has_states": bool(c["states"])} for c in countries()])


class StateListView(APIView):
    """States/provinces for one country (by ISO code or name)."""

    def get(self, request, country):
        from rest_framework.exceptions import NotFound

        from .locations import find_country

        found = find_country(country)
        if found is None:
            raise NotFound("Unknown country.")
        return Response({"code": found["code"], "name": found["name"], "states": found["states"]})

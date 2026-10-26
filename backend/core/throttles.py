from rest_framework.throttling import ScopedRateThrottle


class ScopedThrottle(ScopedRateThrottle):
    """Applies only to the HTTP methods listed in `throttle_methods` (default: writes)."""

    def allow_request(self, request, view):
        methods = getattr(view, "throttle_methods", ("POST", "PUT", "PATCH", "DELETE"))
        if request.method not in methods:
            return True
        return super().allow_request(request, view)

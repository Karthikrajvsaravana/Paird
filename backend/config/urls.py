"""URL configuration for the Paird backend. All API routes are versioned under /api/v1/."""

from django.contrib import admin
from django.urls import include, path

from core.dashboard import DashboardView
from core.views import health

api_v1 = [
    path("health/", health, name="health"),
    path("dashboard/", DashboardView.as_view(), name="dashboard"),
    path("", include("accounts.urls")),
    path("", include("profiles.urls")),
    path("", include("matching.urls")),
    path("", include("messaging.urls")),
    path("", include("safety.urls")),
    path("", include("notifications.urls")),
    path("", include("verification.urls")),
    path("", include("subscriptions.urls")),
]

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include(api_v1)),
]

handler404 = "core.views.json_404"
handler500 = "core.views.json_500"

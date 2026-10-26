from django.urls import path

from . import views

urlpatterns = [
    path("blocks/", views.BlockListView.as_view(), name="blocks"),
    path("blocks/<int:user_id>/", views.UnblockView.as_view(), name="unblock"),
    path("reports/", views.ReportView.as_view(), name="reports"),
    path("reports/reasons/", views.ReportReasonsView.as_view(), name="report-reasons"),
]

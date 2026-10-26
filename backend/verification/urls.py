from django.urls import path

from . import views

urlpatterns = [path("verification/", views.VerificationView.as_view(), name="verification")]

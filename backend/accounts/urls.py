from django.urls import path

from . import views

urlpatterns = [
    path("auth/register/", views.RegisterView.as_view(), name="register"),
    path("auth/login/", views.LoginView.as_view(), name="login"),
    path("auth/refresh/", views.RefreshView.as_view(), name="token-refresh"),
    path("auth/logout/", views.LogoutView.as_view(), name="logout"),
    path("auth/me/", views.MeView.as_view(), name="me"),
    path("auth/change-password/", views.ChangePasswordView.as_view(), name="change-password"),
    path("auth/password-reset/", views.PasswordResetRequestView.as_view(), name="password-reset"),
    path("auth/password-reset/confirm/", views.PasswordResetConfirmView.as_view(), name="password-reset-confirm"),
    path("settings/", views.SettingsView.as_view(), name="settings"),
    path("account/deactivate/", views.DeactivateView.as_view(), name="deactivate"),
    path("account/reactivate/", views.ReactivateView.as_view(), name="reactivate"),
    path("account/delete/", views.DeleteAccountView.as_view(), name="delete-account"),
]

from django.urls import path

from . import views

urlpatterns = [
    path("subscription/", views.SubscriptionView.as_view(), name="subscription"),
    path("subscription/checkout/", views.CheckoutView.as_view(), name="subscription-checkout"),
]

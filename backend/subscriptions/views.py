from rest_framework.response import Response
from rest_framework.views import APIView

from core.exceptions import ServiceUnavailable

from .entitlements import entitlements_for, plans


class SubscriptionView(APIView):
    def get(self, request):
        return Response(
            {
                "entitlements": entitlements_for(request.user),
                "plans": plans(),
                "purchases_enabled": False,
                "purchases_message": "In-app purchases aren't available yet. Premium will be available soon.",
            }
        )


class CheckoutView(APIView):
    def post(self, request):
        # No payment provider is configured. Never simulate a successful purchase.
        raise ServiceUnavailable("In-app purchases aren't available yet.")

from django.contrib.auth import get_user_model
from django.contrib.auth.backends import ModelBackend
from django.core.exceptions import ValidationError

from .identifiers import EMAIL, normalize_identifier
from .models import AccountIdentity


class EmailOrPhoneBackend(ModelBackend):
    """Authenticate with a normalised email address or E.164 phone number."""

    def authenticate(self, request, identifier=None, password=None, **kwargs):
        if identifier is None or password is None:
            return None
        try:
            kind, value = normalize_identifier(identifier)
        except ValidationError:
            return None
        lookup = {"email": value} if kind == EMAIL else {"phone": value}
        identity = AccountIdentity.objects.select_related("user").filter(**lookup).first()
        if identity is None:
            # Run the hasher anyway to reduce timing differences between
            # unknown accounts and wrong passwords.
            get_user_model()().set_password(password)
            return None
        user = identity.user
        if user.check_password(password) and self.user_can_authenticate(user):
            return user
        return None

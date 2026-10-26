"""
Backfill sign-in identities for users created before the accounts app existed
(e.g. a superuser). Only users with a unique, valid email are linked; nothing
is deleted or modified on auth_user. Users without an email can still sign in
to the Django admin with their username.
"""

from django.db import migrations


def backfill(apps, schema_editor):
    User = apps.get_model("auth", "User")
    AccountIdentity = apps.get_model("accounts", "AccountIdentity")
    taken = set(AccountIdentity.objects.exclude(email__isnull=True).values_list("email", flat=True))
    for user in User.objects.filter(identity__isnull=True).exclude(email=""):
        email = user.email.strip().lower()
        if "@" not in email or email in taken:
            continue
        full_name = f"{user.first_name} {user.last_name}".strip() or user.username
        AccountIdentity.objects.create(user=user, full_name=full_name[:150], email=email)
        taken.add(email)


class Migration(migrations.Migration):
    dependencies = [("accounts", "0001_initial")]

    operations = [migrations.RunPython(backfill, migrations.RunPython.noop)]

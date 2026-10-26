"""
Read-only check of the configured database. Never prints passwords, user
names or full connection strings.

    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_dbcheck
"""

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import connection
from django.db.migrations.executor import MigrationExecutor


def _mask_host(host):
    parts = host.split(".")
    if len(parts) <= 3:
        return host[:3] + "…"
    return "…." + ".".join(parts[-3:])


class Command(BaseCommand):
    help = "Verify the active database is the configured Supabase PostgreSQL and report migration status."

    def handle(self, *args, **options):
        db = settings.DATABASES["default"]
        engine = db["ENGINE"]
        host = db.get("HOST", "")
        ok = self.style.SUCCESS("OK")

        self.stdout.write(f"Engine:        {engine}")
        if engine != "django.db.backends.postgresql":
            raise CommandError("The active database is not PostgreSQL. Check DJANGO_SETTINGS_MODULE.")
        self.stdout.write(f"Host:          {_mask_host(host)}")
        if "supabase" not in host.lower():
            self.stdout.write(self.style.WARNING("Warning: DB_HOST does not look like a Supabase host."))
        self.stdout.write(f"Port:          {db.get('PORT')}")
        self.stdout.write(f"SSL mode:      {db.get('OPTIONS', {}).get('sslmode', '(not set)')}")

        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT version(), current_database(), current_setting('ssl', true)")
                version, database, _ = cursor.fetchone()
                cursor.execute("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")
                row = cursor.fetchone()
        except Exception as exc:  # noqa: BLE001 - report without leaking connection details
            raise CommandError(
                f"Could not connect ({exc.__class__.__name__}). Check DB_HOST, DB_PORT, DB_NAME, "
                "DB_USER, DB_PASSWORD and DB_SSLMODE in backend/.env, and that the Supabase project is running."
            ) from None
        self.stdout.write(f"Connection:    {ok} ({version.split(',')[0]})")
        self.stdout.write(f"Database:      {database}")
        if row is not None:
            self.stdout.write(f"TLS in use:    {'yes' if row[0] else 'NO'}")

        executor = MigrationExecutor(connection)
        pending = executor.migration_plan(executor.loader.graph.leaf_nodes())
        if pending:
            self.stdout.write(self.style.WARNING(f"Migrations:    {len(pending)} pending — run 'manage.py migrate'"))
            for migration, _ in pending:
                self.stdout.write(f"                 {migration.app_label}.{migration.name}")
        else:
            self.stdout.write(f"Migrations:    {ok} (all applied)")

        tables = set(connection.introspection.table_names())
        if "accounts_accountidentity" in tables:
            from django.contrib.auth import get_user_model

            from accounts.models import AccountIdentity

            User = get_user_model()
            latest = User.objects.order_by("-date_joined").values_list("date_joined", flat=True).first()
            self.stdout.write(
                f"Users:         {User.objects.count()} total, {AccountIdentity.objects.count()} with app sign-in"
                + (f", newest joined {latest:%Y-%m-%d %H:%M} UTC" if latest else "")
            )

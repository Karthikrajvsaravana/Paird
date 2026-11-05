"""
Check where uploaded photos are stored and that the storage works.
Uploads, reads back and deletes a tiny test file. Never prints keys.

    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_storagecheck
    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_storagecheck --create-bucket

--create-bucket creates the configured bucket (private) if it doesn't exist yet.
"""

import uuid

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Show the photo storage location and test writing to it."

    def add_arguments(self, parser):
        parser.add_argument(
            "--create-bucket",
            action="store_true",
            help="Create the configured bucket (private) if it does not exist yet.",
        )

    def _ensure_bucket(self):
        """Create the bucket through the S3 API if it is missing. Returns True if created."""
        from botocore.exceptions import ClientError

        client = default_storage.connection.meta.client
        bucket = settings.STORAGES["default"]["OPTIONS"]["bucket_name"]
        try:
            client.head_bucket(Bucket=bucket)
            self.stdout.write(f"Bucket check: '{bucket}' exists")
            return False
        except ClientError as exc:
            code = str(exc.response.get("Error", {}).get("Code", ""))
            if code not in ("404", "NoSuchBucket", "NotFound"):
                raise
        region = settings.STORAGES["default"]["OPTIONS"]["region_name"]
        try:
            client.create_bucket(Bucket=bucket)
        except ClientError:
            client.create_bucket(Bucket=bucket, CreateBucketConfiguration={"LocationConstraint": region})
        self.stdout.write(self.style.SUCCESS(f"Created private bucket '{bucket}'"))
        return True

    def handle(self, *args, **options):
        if settings.STORAGE_BACKEND == "s3":
            opts = settings.STORAGES["default"]["OPTIONS"]
            self.stdout.write("Storage:    S3 bucket (nothing is saved on this computer)")
            self.stdout.write(f"Bucket:     {opts['bucket_name']}")
            self.stdout.write(f"Endpoint:   {opts['endpoint_url']}")
            self.stdout.write(f"Region:     {opts['region_name']}")
            self.stdout.write(f"Access key: {'set' if opts['access_key'] else 'NOT SET'}  (value hidden)")
        else:
            self.stdout.write(self.style.WARNING(f"Storage:    this computer's disk — {settings.MEDIA_ROOT}"))
            self.stdout.write("            Set STORAGE_BACKEND=s3 and the STORAGE_S3_* values in backend/.env to use a bucket.")

        name = f"healthcheck/{uuid.uuid4().hex}.txt"
        try:
            if options.get("create_bucket"):
                if settings.STORAGE_BACKEND != "s3":
                    raise CommandError("--create-bucket only applies when STORAGE_BACKEND=s3.")
                self._ensure_bucket()
            saved = default_storage.save(name, ContentFile(b"paird storage check"))
            with default_storage.open(saved, "rb") as handle:
                ok = handle.read() == b"paird storage check"
            default_storage.delete(saved)
        except CommandError:
            raise
        except Exception as exc:  # noqa: BLE001 - report clearly without secrets
            message = str(exc)[:200]
            hint = ""
            if "NoSuchBucket" in message:
                hint = (
                    " The bucket doesn't exist (names are case-sensitive). Run this command again with"
                    " --create-bucket to create it, or fix STORAGE_S3_BUCKET in backend/.env."
                )
            elif "InvalidAccessKeyId" in message or "SignatureDoesNotMatch" in message or "403" in message:
                hint = " Check STORAGE_S3_ACCESS_KEY_ID, STORAGE_S3_SECRET_ACCESS_KEY and STORAGE_S3_REGION."
            raise CommandError(f"Storage test failed ({exc.__class__.__name__}: {message}).{hint}") from None
        if not ok:
            raise CommandError("Storage test failed: the file read back did not match.")
        self.stdout.write(self.style.SUCCESS("Write/read/delete test: OK"))

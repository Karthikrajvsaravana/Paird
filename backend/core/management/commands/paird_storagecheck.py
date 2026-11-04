"""
Check where uploaded photos are stored and that the storage works.
Uploads, reads back and deletes a tiny test file. Never prints keys.

    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_storagecheck
"""

import uuid

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Show the photo storage location and test writing to it."

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
            saved = default_storage.save(name, ContentFile(b"paird storage check"))
            with default_storage.open(saved, "rb") as handle:
                ok = handle.read() == b"paird storage check"
            default_storage.delete(saved)
        except Exception as exc:  # noqa: BLE001 - report clearly without secrets
            message = str(exc)[:200]
            hint = ""
            if "NoSuchBucket" in message:
                hint = " The bucket name is wrong or the bucket doesn't exist."
            elif "InvalidAccessKeyId" in message or "SignatureDoesNotMatch" in message or "403" in message:
                hint = " Check STORAGE_S3_ACCESS_KEY_ID, STORAGE_S3_SECRET_ACCESS_KEY and STORAGE_S3_REGION."
            raise CommandError(f"Storage test failed ({exc.__class__.__name__}: {message}).{hint}") from None
        if not ok:
            raise CommandError("Storage test failed: the file read back did not match.")
        self.stdout.write(self.style.SUCCESS("Write/read/delete test: OK"))

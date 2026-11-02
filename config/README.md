# Local app configuration

`dev.json` holds your own development settings for the Flutter app and is
**not committed** (it is in `.gitignore`). Create it once from the example:

```powershell
Copy-Item config\dev.example.json config\dev.json
notepad config\dev.json
```

Set `API_BASE_URL` to `http://<your-PC-LAN-IP>:8001/api/v1`. Never put
passwords or keys in this file — it is compiled into the app.
The "Paird app (phone)" run configuration in Android Studio reads it with
`--dart-define-from-file=config/dev.json`.

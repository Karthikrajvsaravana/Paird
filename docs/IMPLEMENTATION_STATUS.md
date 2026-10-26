# Paird — Implementation Status

_Last updated: 2026-10-26_

This file records what is actually implemented and verified, what is blocked by external services, and how to run everything on Windows. Product rules, the Vibe Score formula, the API reference and the security model are in [README.md](../README.md).

## Contents

1. [Architecture](#architecture)
2. [Feature status](#feature-status)
3. [Supabase and database](#supabase-and-database)
4. [Test and verification results](#test-and-verification-results)
5. [Run on your physical Android phone (Windows PowerShell)](#run-on-your-physical-android-phone-windows-powershell)
6. [Running tests](#running-tests)
7. [External services still needed](#external-services-still-needed)
8. [Known limitations](#known-limitations)
9. [Next steps](#next-steps)

## Architecture

```
Flutter app (Android)  ──HTTPS/JSON + JWT──▶  Django REST Framework (/api/v1)  ──Django ORM──▶  Supabase PostgreSQL
```

- Flutter never connects to PostgreSQL and contains no database or Supabase credentials. Its only configuration is the API URL (`API_BASE_URL`).
- Django reads every secret from `backend/.env`. `DATABASES` is PostgreSQL only, with no SQLite fallback.
- Authentication uses JWT:
  - The access token lasts 15 minutes and is kept in memory.
  - The refresh token lasts 30 days, is rotated and blacklisted on use, and is stored in Android Keystore-backed secure storage.
- Backend apps: `accounts`, `profiles`, `matching`, `messaging`, `safety`, `notifications`, `verification`, `subscriptions`, `core`.
- Flutter is organised by feature: `lib/features/<area>/screens`. Shared code lives in `lib/core` (API client, auth, models) and `lib/shared/widgets`.

## Feature status

| # | Area | Status | Notes |
|---|---|---|---|
| 1 | Sign in | Done | Email or phone plus password. The original slide-to-sign-in is kept and also works with screen readers. |
| 2 | Sign up | Done | Original form. Validated in the app and on the server; duplicate accounts are blocked by a unique constraint; submit is locked while saving; errors come from the server. |
| 3 | Forgot / reset password | Done (needs SMTP) | 6-digit email code, single use, 15-minute expiry, 5 attempts. The reply never reveals whether an account exists. SMS reset needs a provider. |
| 4 | Onboarding | Done | 10 steps, saved to the server after each step and resumable. |
| 5 | Profile completion | Done | Server computes the percentage and the missing required fields; publishing is blocked until they're complete. |
| 6 | Dashboard | Done | Real counts, notices and recommendations; nothing invented. |
| 7 | Discover | Done | Server-side eligibility and privacy rules, filters, paging, empty and error states. |
| 8 | Matches and interests | Done | Send, accept, decline, withdraw, 7-day expiry enforced on the server, idempotent, mutual interest becomes a match, end match. |
| 9 | Messaging | Done (polling) | Matched members only, membership checked on every request, history paging, unread counts, read receipts. Not real-time; see limitations. |
| 10 | Partner preferences | Done | Validated on the server and used by Discover and the Vibe Score. |
| 11 | Vibe Score | Done | Transparent rules-based preference fit, documented and tested. No AI and no claim that it predicts compatibility. |
| 12 | Profile viewing | Done | Filtered by privacy; email, phone, surname and exact date of birth are never shown. |
| 13 | Profile editing | Done | Every section, name, and photos (upload, delete, main photo; location data stripped). |
| 14 | Verification | Done (staff review) | Pending / approved / rejected / unverified. Only staff can approve, in the Django admin. It's a photo check, **not** an ID check, and the selfie is deleted after review. |
| 15 | Premium | Partial | Plans, entitlements and the daily-interest limit are enforced on the server. **Purchases are disabled**: no payment provider is configured and nothing is simulated. |
| 16 | Settings | Done | |
| 17 | Privacy and discoverability | Done | Discoverable, photo / income / lifestyle visibility, who can send interests, who can message, last-seen. All enforced in the API. |
| 18 | Notifications | Partial | In-app notifications and their settings work. Push notifications need Firebase. |
| 19 | Account management | Done | Change name, change password (signs out other devices), block list, deactivate / reactivate, permanent delete. |
| 20 | Logout | Done | Revokes the refresh token on the server, clears secure storage, returns to sign in. |
| — | Google sign-in | Not implemented | Needs an OAuth client. The button says it isn't available. |

## Supabase and database

### Environment variables

Use names only and keep the values in `backend/.env`, which is gitignored.

- **Required:** `DJANGO_SECRET_KEY`, `DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_SSLMODE`
- **Optional:**
  - JWT: `JWT_SIGNING_KEY`, `JWT_ACCESS_MINUTES`, `JWT_REFRESH_DAYS`
  - Browser and HTTPS: `CORS_ALLOWED_ORIGINS`, `CSRF_TRUSTED_ORIGINS`, `DJANGO_SECURE_SSL_REDIRECT`, `DJANGO_BEHIND_HTTPS_PROXY`
  - Email: `EMAIL_*`
  - Storage: `STORAGE_*`
  - Product rules: `PAIRD_*`
- **Tests only:** `TEST_DB_NAME`, `TEST_DB_USER`, `TEST_DB_PASSWORD`, `TEST_DB_HOST`, `TEST_DB_PORT`, `TEST_DB_SSLMODE`. These must point at a separate test database.

### Checking the connection without exposing secrets

```powershell
.\backend\.venv\Scripts\python.exe .\backend\manage.py paird_dbcheck
```

This prints:
- the engine, which must be PostgreSQL;
- the end of the host name, with a warning if it isn't a Supabase host;
- the port and SSL mode, and whether TLS is actually in use;
- whether the connection works, plus pending migrations;
- user counts.

It never prints the password, user name or full host. If the connection fails, it lists which variable names to check.

### Migration status

- Your database already had Django's default migrations, with `auth.User`. That user model is **kept**; nothing alters or drops existing tables.
- New migrations, which create tables only:
  - `accounts` 0001–0002 (0002 links existing users that have an email so they can sign in)
  - `profiles` 0001, `safety` 0001, `matching` 0001, `messaging` 0001, `notifications` 0001, `verification` 0001, `subscriptions` 0001
  - `token_blacklist` 0001–0013
- **They have not been applied to your Supabase database yet.** That's step 2 under [Next steps](#next-steps).
- `makemigrations --check` reports no missing migrations.

## Test and verification results

The sandbox below is the cloud development environment, not your PC or Supabase.

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | **25 passed**. Covers startup, sign-in / sign-up navigation, form validation, sign-up and sign-in success and failure, API errors, session restore, expired session, logout, main tab navigation and empty states, and sending an interest from Discover. The API is mocked. |
| Backend `manage.py check` | No issues |
| `makemigrations --check --dry-run` | No changes |
| Backend tests | **98 passed on PostgreSQL 16** in the sandbox, using the PostgreSQL-only test settings. Covers registration, duplicates, invalid input, password hashing (PBKDF2), login, wrong password, authentication, IDOR / unauthorised profile access, profile editing, Discover privacy, interest transitions and expiry, compatibility, conversation membership, message authorisation, preferences and privacy, premium limits, client-side tampering with premium or verification, and database constraints. |
| End-to-end in a browser | In an earlier round, a web build of the app was driven against the real Django API (sandbox PostgreSQL). Sign up, all onboarding steps, photo upload, publish, sign in, Discover, send interest, accept (other user), match and chat all worked with no console errors. |
| **Not run** | Anything against **your Supabase** database (no credentials in the sandbox, which is correct); backend tests on a Supabase test project; an **Android build** (the Android SDK download host is blocked in the sandbox); anything on your **physical phone**. |

## Run on your physical Android phone (Windows PowerShell)

Run everything from the project folder (`cd E:\Dev\paird`). No `.ps1` or `.bat` scripts are needed.

### 1. Check the backend

```powershell
.\backend\.venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt
.\backend\.venv\Scripts\python.exe .\backend\manage.py check
.\backend\.venv\Scripts\python.exe .\backend\manage.py paird_dbcheck
.\backend\.venv\Scripts\python.exe .\backend\manage.py migrate --plan
.\backend\.venv\Scripts\python.exe .\backend\manage.py migrate
```

### 2. Find your PC's LAN IP address

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match 'Wi-Fi|Ethernet' -and $_.IPAddress -notlike '169.254.*' } | Select-Object InterfaceAlias, IPAddress
```

Use the address of the adapter that is on the same Wi-Fi network as your phone, for example `192.168.x.x`. Below it's written as `<PC-IP>`. It can change when you reconnect, so check it again if the phone stops connecting.

### 3. Allow the phone through

In `backend\.env`, set:
- `DJANGO_DEBUG=True` (local development only)
- `DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,<PC-IP>`

Your Wi-Fi network must be set to **Private**. Check with:

```powershell
Get-NetConnectionProfile
```

Then open port 8001 for private networks only. Run this **once**, in PowerShell started with "Run as administrator":

```powershell
New-NetFirewallRule -DisplayName "Paird Django dev (8001)" -Direction Inbound -Protocol TCP -LocalPort 8001 -Action Allow -Profile Private
```

### 4. Start Django so other devices can reach it

```powershell
.\backend\.venv\Scripts\python.exe .\backend\manage.py runserver 0.0.0.0:8001
```

Check it from the **phone's browser** by opening `http://<PC-IP>:8001/api/v1/health/`. You should see `{"status":"ok","database":"ok"}`. If the page doesn't load, recheck steps 2–3.

### 5. Run the app on the phone

On the phone, enable Developer options and USB debugging, connect it by USB, and accept the prompt. Then:

```powershell
flutter devices
flutter run -d <device-id> --dart-define=API_BASE_URL=http://<PC-IP>:8001/api/v1
```

Without `API_BASE_URL`, debug builds use `10.0.2.2`, which only works on the emulator. In that case the app's error message tells you to set it.

### 6. Build an APK for local testing

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=http://<PC-IP>:8001/api/v1
```

The output is `build\app\outputs\flutter-apk\app-debug.apk`. Copy it to the phone and install it.

Use a **debug** APK for local HTTP testing. Release APKs require an HTTPS API (`--dart-define=API_BASE_URL=https://…`), a real application ID, and a signing key; see README "Android release".

### 7. Verify that registration reached Supabase

After signing up in the app, run `paird_dbcheck` again. The "Users" total should go up and "newest joined" should show the sign-up time. Account details are visible in the Django admin (`http://127.0.0.1:8001/admin/`) after you run `createsuperuser`.

## Running tests

### Backend

Needs a **dedicated** PostgreSQL test database. Create a second Supabase project for testing and put its connection details in `TEST_DB_*` in `backend\.env`.

```powershell
$env:DJANGO_SETTINGS_MODULE = "config.settings_test"
.\backend\.venv\Scripts\python.exe .\backend\manage.py test accounts core profiles matching messaging safety verification subscriptions --noinput
Remove-Item Env:DJANGO_SETTINGS_MODULE
```

The test settings refuse to start without `TEST_DB_*`, or if `TEST_DB_*` matches your app database.

If Supabase doesn't let the test runner create its temporary `test_<name>` database, add `--keepdb` after creating that database once in the test project.

### Flutter

```powershell
flutter pub get
flutter analyze
flutter test
```

## External services still needed

| Service | Needed for | Status without it |
|---|---|---|
| SMTP (`EMAIL_HOST`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, `DEFAULT_FROM_EMAIL`) | Password reset emails | Debug mode prints the code in the Django console. Production returns "not configured". |
| SMS provider | Phone-number password reset | The app says it isn't available. |
| Google OAuth client and SHA-1 | Google sign-in | The button says it isn't available. |
| Firebase Cloud Messaging | Push notifications | In-app notifications and badges only. |
| Google Play Billing (or Stripe) and server receipt verification | Buying Premium | Purchases disabled. Staff can grant Premium in the admin. |
| KYC / ID provider | Identity-document verification | Staff photo review only, labelled honestly. |
| Private S3-compatible storage (e.g. Supabase Storage) | Photos in production | Photos are stored on the server's disk (`backend/media`, gitignored). |
| Redis plus Django Channels | Real-time chat | Polling (5 s in chat, 30 s list, 60 s badges). |
| HTTPS hosting and a domain | Release builds and production | Debug builds over LAN only. |

## Known limitations

- Messaging uses polling, not real-time delivery.
- The prototype `docs/reference/paird-prototype.html` is not in the repository. Field sets and the 7-day interest expiry follow the written brief.
- Discover filters list fields in Python after a 500-candidate database query. That's fine at launch scale; see README.
- The app ID is still `com.example.paird`, and the launcher icon is the Flutter default.
- Nothing has been verified on your Supabase database or your phone yet.

## Next steps

1. **Get this code onto your PC.** It's on branch `claude/gracious-mccarthy-q659ik` once it has been pushed. If you applied `paird-flutter-fixes.patch` earlier, run `git stash` first; the branch already includes those fixes. Then:
   ```powershell
   git fetch origin
   git switch claude/gracious-mccarthy-q659ik
   ```
2. Install the requirements, run `paird_dbcheck`, then `migrate --plan` and `migrate` (section 1 above).
3. Follow sections 2–5 to run the app on your phone, then register a test account and confirm it with `paird_dbcheck` (section 7).
4. Optional: create a Supabase **test** project, fill in `TEST_DB_*`, and run the backend tests.
5. Before a store release, decide the application ID, create a signing key, set up HTTPS hosting, configure SMTP, and enable row-level security on Django's tables in Supabase.

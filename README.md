# PairD

PairD is a matrimony app: a Flutter client (Android first) backed by a Django REST Framework API on Supabase-hosted PostgreSQL.

## Contents

- [Project structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Backend setup](#backend-setup)
- [Flutter setup and running on Android](#flutter-setup-and-running-on-android)
- [Running tests](#running-tests)
- [Product rules](#product-rules)
- [Vibe Score](#vibe-score)
- [API reference](#api-reference)
- [Security model](#security-model)
- [Production deployment](#production-deployment)
- [Android release](#android-release)
- [Known limitations and external blockers](#known-limitations-and-external-blockers)

## Project structure

```
backend/                     Django project (run from the repo root, see below)
  config/                    settings.py (env-driven), settings_test.py, urls.py
  core/                      error envelope, throttling, health, dashboard, activity tracking
  accounts/                  email-or-phone sign-in identity, JWT auth, password reset, account lifecycle
  profiles/                  profile, partner preferences, photos, privacy, onboarding rules
  matching/                  discovery, Vibe Score, interests (7-day expiry), matches
  messaging/                 conversations, messages, read state (polling)
  safety/                    blocks and reports
  notifications/             in-app notifications and preferences
  verification/              photo verification by staff review
  subscriptions/             Premium plans and server-side entitlements
  requirements.txt
  .env.example               every supported variable, placeholders only
lib/
  main.dart                  bootstraps services and PairdApp
  app/                       PairdApp, AuthGate (routing by session state), AppScope, theme
  core/                      ApiClient (token refresh), PairdApi, AuthController, models, validators
  shared/widgets/            reusable widgets in the PairD style
  features/                  auth, onboarding, dashboard, discover, matches, messaging,
                             profile, settings, verification, premium, notifications, safety
test/                        Flutter unit and widget tests
```

The prototype referenced during planning (`docs/reference/paird-prototype.html`) is **not in the repository**. Where the brief listed a feature but no specification existed, the choices made are documented below under [Product rules](#product-rules).

## Prerequisites

- Flutter 3.47 (Dart 3.13), Android Studio / Android SDK, and an emulator or device
- Python 3.12+ with the virtual environment at `backend\.venv`
- A Supabase project (PostgreSQL connection string)

## Backend setup

All commands run from the repository root in PowerShell. The virtual environment is used directly and never needs activating.

1. Install dependencies:
   ```powershell
   .\backend\.venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt
   ```
2. Configure `backend\.env`. Use `backend\.env.example` as the reference, but **do not overwrite your existing `.env`**; add any new variables it is missing.
   - For local development set `DJANGO_DEBUG=True`. With `DJANGO_DEBUG=False` the server enforces HTTPS redirects and secure cookies, which breaks plain-HTTP local testing.
   - Add your PC's LAN IP (for a physical phone) and/or `10.0.2.2` (for the emulator) to `DJANGO_ALLOWED_HOSTS`.
   - Generate a secret key with:
     ```powershell
     .\backend\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(64))"
     ```
3. Check the configuration, confirm Django is connected to Supabase over SSL (no secrets are printed), and review the pending migrations:
   ```powershell
   .\backend\.venv\Scripts\python.exe .\backend\manage.py check
   .\backend\.venv\Scripts\python.exe .\backend\manage.py paird_dbcheck
   .\backend\.venv\Scripts\python.exe .\backend\manage.py showmigrations
   .\backend\.venv\Scripts\python.exe .\backend\manage.py migrate --plan
   ```
4. Apply the migrations to the configured database:
   ```powershell
   .\backend\.venv\Scripts\python.exe .\backend\manage.py migrate
   ```
5. Run the API on port 8001:
   ```powershell
   .\backend\.venv\Scripts\python.exe .\backend\manage.py runserver 0.0.0.0:8001
   ```
   Check it is up with `Invoke-RestMethod http://127.0.0.1:8001/api/v1/health/`.
6. Create a staff account so you can review reports and verification requests at `/admin/`:
   ```powershell
   .\backend\.venv\Scripts\python.exe .\backend\manage.py createsuperuser
   ```

### Migration notes

The existing database already used Django's default `auth.User`. This project **keeps** it; it does not swap `AUTH_USER_MODEL`.

- Sign-in identities (normalised email or E.164 phone) live in `accounts.AccountIdentity`, a one-to-one table with uniqueness constraints.
- All new migrations only **create new tables**. Nothing on `auth_user` or other existing tables is altered or dropped.
- `accounts.0002_backfill_identities` links existing users that have an email address to an identity, so they can sign in with that email. Users without an email can still use the admin with their username.
- `rest_framework_simplejwt.token_blacklist` adds two tables for refresh-token revocation.

The full migration sequence was rehearsed in the development sandbox on a disposable PostgreSQL 16 server that started in the same state as yours: default migrations applied, plus a pre-existing user. It has **not** yet been run against your Supabase database.

## Flutter setup and running on Android

Step-by-step Windows instructions for a **physical phone** (finding your PC's LAN IP, firewall, `ALLOWED_HOSTS`, running and building) are in [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md#run-on-your-physical-android-phone-windows-powershell).

- **Physical phone:** `flutter run --dart-define=API_BASE_URL=http://<your-PC-LAN-IP>:8001/api/v1`
- **Emulator:** plain `flutter run` uses `http://10.0.2.2:8001/api/v1`, which is the PC as seen from the emulator.
- Plain HTTP is only allowed in **debug** builds (`android/app/src/debug/AndroidManifest.xml`). Release builds require HTTPS.

The API base URL is a build-time setting (`lib/core/config/app_config.dart`), so no secrets are compiled into the app. Flutter only talks to the Django API: never to PostgreSQL, and never with Supabase keys.

## Running tests

### Backend

Tests run on **PostgreSQL only**; there is no SQLite fallback. They need a **dedicated test database**, for example a separate Supabase project used only for testing. Put `TEST_DB_NAME`, `TEST_DB_USER`, `TEST_DB_PASSWORD`, `TEST_DB_HOST`, `TEST_DB_PORT` and `TEST_DB_SSLMODE` in `backend\.env` (see `.env.example`).

`config.settings_test` refuses to run if the variables are missing, or if they point at the same database as `DB_*`. Django creates a temporary `test_<TEST_DB_NAME>` database there and drops it afterwards.

```powershell
$env:DJANGO_SETTINGS_MODULE = "config.settings_test"
.\backend\.venv\Scripts\python.exe .\backend\manage.py test accounts core profiles matching messaging safety verification subscriptions --noinput
Remove-Item Env:DJANGO_SETTINGS_MODULE
```

Other checks (these use your real `.env`, read-only):

```powershell
.\backend\.venv\Scripts\python.exe .\backend\manage.py check
.\backend\.venv\Scripts\python.exe .\backend\manage.py paird_dbcheck
.\backend\.venv\Scripts\python.exe .\backend\manage.py makemigrations --check --dry-run
```

### Flutter

```powershell
flutter analyze
flutter test
```

## Product rules

These are server-side rules. The app only displays them. Values marked as settings can be changed in `.env`.

| Rule | Behaviour |
|---|---|
| Minimum age | 18 (`PAIRD_MIN_AGE`), checked on date of birth and on preference ranges |
| Sign-in identifier | One email **or** one phone number in international format (`+<country code>…`). `PAIRD_DEFAULT_PHONE_COUNTRY_CODE` can prefix local numbers. |
| Passwords | Django's validators: at least 8 characters, not common, not all digits, not similar to your name or email |
| Publishing a profile | Required: gender, "looking for", date of birth, marital status, city, country, education, occupation, marriage timeline, and consent. Everything else is optional. |
| Discovery eligibility | Published, discoverable, not deactivated, active account, not you, not blocked either way, not already matched, no pending interest already sent by you. Gender and age preferences must be satisfied **in both directions**. |
| Interests | One pending interest per pair. Repeating the request is idempotent. Mutual interest becomes a match automatically. |
| Interest expiry | Pending interests expire **7 days** after sending (`PAIRD_INTEREST_EXPIRY_DAYS`), enforced on every interest operation. The 7-day value comes from the brief; the prototype was not available to confirm it. Optionally run `manage.py expire_interests` hourly to persist expiry. |
| Declines | After a decline, the sender cannot re-send for 30 days (`PAIRD_DECLINE_COOLDOWN_DAYS`) |
| Daily limit | Free members can send 10 interests per rolling 24 hours (`PAIRD_FREE_DAILY_INTEREST_LIMIT`). Premium is unlimited. |
| Messaging | Only between active matches. Optional "verified matches only" setting. Up to 2,000 characters. |
| Blocking | Ends the match, closes pending interests both ways, and hides each member from the other everywhere |
| Deactivation | Hides the profile, and stops new interests and messages. Reversible by the member. |
| Deletion | Permanent. Requires the password. Removes the profile, photos (including stored files), interests, matches and messages. |

## Vibe Score and AI matching

PairD matching has two layers.

### 1. Match engine: the Vibe Score (rules-based, always on)

`backend/matching/compatibility.py` scores how well two members fit **each other**, from 0 to 100. It is deterministic, free to run, and tested.

| Factor | Weight | How it's scored |
|---|---|---|
| Your preferences | 30 | Share of the partner preferences *you* set that they meet (only fields you're allowed to see) |
| What they're looking for | 30 | Share of *their* preferences you meet. It's applied, but their preferences are never shown to you. |
| Children | 12 | Same answer 1.0, "open" 0.7. Yes vs no is a **deal-breaker** that caps the total at 35. |
| Marriage timeline | 9 | Same 1.0, adjacent 0.7, otherwise 0.35. "Not sure" 0.6. |
| Lifestyle | 8 | Diet, smoking and drinking similarity, used only if their lifestyle is visible to you |
| Location | 6 | Same city 1.0, same state 0.85, same country 0.7. Abroad depends on willingness to relocate. |
| Family values | 3 | Same 1.0, adjacent 0.7 |
| Living arrangement | 2 | Same 1.0, "flexible" 0.8 |

How the total is calculated:
- Only factors with data on both sides count.
- Unmet stated preferences then **scale the total down**, from either side, so shared hobbies can't outweigh what someone explicitly asked for. Each side's factor is `0.7 + 0.3 × fit`.
- Religion, education, income and occupation count **only through members' own preferences**. The engine never assumes anything from them on its own.

Discover (sort **Best matches**, the default) and the dashboard recommendations use this score. The Vibe Score shown in the app is this score, with a breakdown that lists only factor names.

### 2. AI match insight (Anthropic Claude, optional)

When a member opens a profile, the backend (`backend/matching/ai.py`) asks Claude (`claude-opus-5-5` by default) for a short assessment:
- a rating (Strong / Good / Worth exploring / Low);
- a summary, what fits, and what's worth talking about;
- a conversation opener.

**What Claude sees:**
- The viewer's own profile and preferences.
- Only what the viewer is allowed to see of the other member.
- Never: names, email or phone, photos, exact date of birth, community, or the other member's own preferences.
- Free text such as "about me" is passed as data, so a profile can't instruct the AI.

**Controls:**
- Insights are cached per pair, and recomputed only when the data sent would change.
- Each member gets a daily limit of new insights (`PAIRD_AI_DAILY_LIMIT`).
- Members can opt out in Settings → **AI match insights**. If either member opts out, no insight is made.
- Refusals use `fallbacks: "default"`.
- If anything fails, the card shows a calm message and no partial insight is stored.

**Turning it on:**
1. Set `ANTHROPIC_API_KEY` in `backend/.env`; it stays on the backend only.
2. Install the requirements.
3. Restart the backend.

Without a key, the AI card is hidden and everything else works.

Cost is a few US cents per new insight at Claude Opus 5.5 prices; cached insights cost nothing. Mention AI processing in your privacy policy before launch.

### Demo profiles for testing

```powershell
.\backend\.venv\Scripts\python.exe .\backend\manage.py paird_seed_demo
.\backend\.venv\Scripts\python.exe .\backend\manage.py paird_seed_demo --remove
```

The first command creates 10 women and 10 men, the second removes them all. They use `@demo.paird.test` emails, the password `PairD-Demo-2026!` (change it with `--password`), generated initials photos, and an "(Demo profile for testing.)" note on each profile. The profiles are designed as 10 intended pairs, and `matching/tests/test_engine.py` checks that the engine ranks every member's intended partner first. **Never run this on a production database with real members.**

## API reference

All routes are under `/api/v1/` and use JSON with `Authorization: Bearer <access token>`.

Every error uses the same envelope:

```json
{"error": {"code": "...", "message": "...", "fields": {"field": ["..."]}}}
```

| Area | Endpoints |
|---|---|
| Health | `GET health/` (public) |
| Auth | `POST auth/register/`, `auth/login/`, `auth/refresh/`, `auth/logout/`; `GET/PATCH auth/me/`; `POST auth/change-password/`, `auth/password-reset/`, `auth/password-reset/confirm/` |
| Account | `GET/PATCH settings/` (privacy and notifications); `POST account/deactivate/`, `account/reactivate/`, `account/delete/` |
| Locations | `GET locations/countries/`; `GET locations/countries/<code>/states/` (country and state pickers; profile and preference countries are validated against this list) |
| Profile | `GET options/`; `GET/PATCH profile/me/`; `POST profile/me/publish/`; `GET/PUT/PATCH preferences/` |
| Photos | `GET/POST photos/`; `PATCH/DELETE photos/<id>/`; `GET photos/<id>/file/` (authorised stream) |
| Members | `GET members/<user_id>/` (privacy-filtered); `GET members/<user_id>/insight/` (AI match insight: `{status, insight, message}`) |
| Discovery | `GET discover/?sort=best\|recent&page=&age_min=&age_max=&religion=&country=&city=&education_level=&marital_status=&marriage_timeline=&verified_only=&with_photo=` |
| Dashboard | `GET dashboard/` |
| Interests | `GET interests/?direction=received\|sent&status=pending\|…`; `POST interests/`; `POST interests/<id>/accept\|decline\|withdraw/` |
| Matches | `GET matches/`; `POST matches/<id>/end/` |
| Messages | `GET conversations/`; `GET conversations/<id>/messages/?before=<id>\|after=<id>`; `POST conversations/<id>/messages/`; `POST conversations/<id>/read/` |
| Safety | `GET/POST blocks/`; `DELETE blocks/<user_id>/`; `POST reports/`; `GET reports/reasons/` |
| Notifications | `GET notifications/`; `POST notifications/read-all/` |
| Verification | `GET/POST verification/` (multipart `selfie`) |
| Premium | `GET subscription/`; `POST subscription/checkout/` (returns 503 until payments are integrated) |

## Security model

### Authentication

- JWTs: 15-minute access tokens and 30-day refresh tokens.
- Refresh tokens rotate and are blacklisted on use. Logout, password change, password reset and account deletion revoke them.
- The app keeps the access token in memory only. The refresh token is in `flutter_secure_storage` (Android Keystore-backed). Passwords are never stored.
- `android:allowBackup="false"` keeps credentials out of device backups.

### Authorisation

- Every rule is enforced server-side, including object-level checks: profiles, photo files, interests, matches, conversations and messages.
- Blocked, deactivated, unpublished or hidden members return `404`, so their existence isn't revealed.

### Privacy

- Other members never receive email, phone, surname or exact date of birth.
- Photo, income, lifestyle and last-seen visibility are applied in the API responses themselves.

### Uploads

- JPEG/PNG/WebP only, at most 5 MB, at least 200 px.
- Images are re-encoded server-side, which strips EXIF and GPS data.
- Files are stored privately and served only through an authorisation check.

### Abuse limits

Scoped throttles apply to authentication, interests, messages, uploads and reports.

### Error handling

- In production, errors return generic JSON and never Django debug pages.
- `check --deploy` passes apart from HSTS preload, which is deliberately left off because it is hard to reverse.

## Production deployment

1. **Host the API** on any WSGI host, for example `gunicorn config.wsgi` behind HTTPS.
2. **Set the production environment:**
   - `DJANGO_DEBUG=False`
   - `DJANGO_ALLOWED_HOSTS=<your API domain>`
   - A long random `DJANGO_SECRET_KEY`
   - `DJANGO_BEHIND_HTTPS_PROXY=True` if TLS terminates at a proxy
3. **Static and media files:**
   - Run `manage.py collectstatic`.
   - For uploads, use a **private** Supabase Storage bucket: set `STORAGE_BACKEND=s3` and the `STORAGE_S3_*` variables (see `.env.example`), then run `manage.py paird_storagecheck`. `manage.py paird_move_media` copies photos already saved on disk into the bucket. Never make the bucket public: the API streams each photo after its own permission check.
4. **Shared cache:** with more than one process, configure a shared cache (for example Redis) so throttling works across processes.
5. **Email:** configure SMTP (`EMAIL_*`) to send welcome emails after email sign-up and password reset codes. Welcome emails are sent only after the account is saved, and a mail failure never fails registration (`PAIRD_WELCOME_EMAIL_ENABLED`, `PAIRD_SUPPORT_EMAIL`).
6. **Scheduled expiry (optional):** schedule `manage.py expire_interests` hourly. Expiry is also enforced on every request.
7. **Database:**
   - Use least-privilege database credentials and enable Supabase backups / point-in-time recovery.
   - Because Django tables live in the `public` schema, enable row-level security on them (or revoke the `anon` and `authenticated` roles) so they aren't reachable through Supabase's auto-generated REST API. Django connects as the database owner and is unaffected.

## Android release

What's already done:
- `INTERNET` permission and the "PairD" label in the main manifest
- Cleartext HTTP allowed in debug builds only
- `allowBackup=false`
- Release signing read from `android/key.properties` (gitignored)
- Camera and photo-library usage strings on iOS

**Required from you before a store release:**

1. **Application ID.** It is still `com.example.paird` (`android/app/build.gradle.kts`, `namespace` and `applicationId`, and the Kotlin package in `MainActivity.kt`). Choose your permanent ID; it cannot be changed after the first Play upload.
2. **Signing key.** Create one:
   ```powershell
   keytool -genkey -v -keystore $env:USERPROFILE\paird-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Then create `android\key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Never commit it.
3. **Production API URL** over HTTPS.
4. **Launcher icon.** Still the Flutter default.

Build:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.your-domain.example/api/v1
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.your-domain.example/api/v1
```

The outputs are `build\app\outputs\flutter-apk\app-release.apk` and `build\app\outputs\bundle\release\app-release.aab`.

## Data licences

Country and state names come from the Countries States Cities Database (ODbL 1.0). See `backend/core/data/LOCATIONS_LICENSE.md` for the attribution and source notices.

## Known limitations and external blockers

| Feature | Status |
|---|---|
| Prototype (`docs/reference/paird-prototype.html`) | Not in the repository. Field sets, plan presentation and the 7-day expiry follow the written brief. |
| Google sign-in | Not available. Needs a Google Cloud OAuth client and SHA-1 fingerprints. The buttons say it isn't available yet. |
| Password reset by SMS | Not available. Needs an SMS provider. Email reset works once SMTP is configured. |
| Push notifications | Not available. Needs Firebase Cloud Messaging. In-app notifications and badges work. |
| Real-time messaging | Not available. Chat **polls** every 5 seconds while a conversation is open (30 seconds for the list, 60 seconds for badges). WebSockets (Django Channels + Redis) would be the upgrade path. |
| Payments | No provider is integrated, so no purchase is simulated. Entitlements are stored server-side (`subscriptions.Subscription`) and can be granted by staff in the admin. Google Play Billing integration needs a Play Console product plus server-side receipt verification that creates `Subscription` rows. |
| Identity verification | Verification is **photo review by staff**, not an identity-document check, and the UI says exactly that. Document verification would need a KYC provider. |
| Discovery scale | Candidates are filtered in the database, then capped at 500 (`PAIRD_DISCOVERY_CANDIDATE_CAP`) before reciprocal-preference filtering. That's fine for launch scale; move list filters into the database (PostgreSQL arrays/JSONB) as membership grows. |
| Android build | Not built in the development container, because the Android SDK download host was blocked by its network policy. Build locally (see `docs/IMPLEMENTATION_STATUS.md`). |

# dayfello — Handover

> Living document. Updated with every change. Newest entries first in the **Change log** at the bottom.

## 1. What this is
**dayfello** is a marketplace for booking verified human companions ("Fellows") by the hour. It covers 9 services: Senior, Patient, Child, Travel, Pet, Event, Shopping, Family and Railway. Customers book and track a Fellow live, Fellows accept and run jobs, and an operations team verifies Fellows and monitors safety.

| Part | Folder | Stack |
|---|---|---|
| Mobile + web app (customer, Fellow and admin in one app, chosen by login role) | `app/` | Flutter 3 (Android, iOS, Web), provider, flutter_map, Firebase Messaging |
| Backend API | `backend/` | Django + Django REST Framework, PostgreSQL, JWT (SimpleJWT) |

## 2. Repositories and branches
- **Current code:** `github.com/tamaraiselvan/Companion-Application-test`, branch `claude/upbeat-clarke-lg6nig`.
- **Target repo:** `DayFello`. Locally it is `D:\GitHub Repositories\DayFello`. All commits there must be authored by **tamaraiselvan** only.
  - *Status:* not yet reachable from the cloud session. GitHub reports it as not found or no access. Fix by pushing the repo to GitHub as `tamaraiselvan/DayFello` and granting the Claude GitHub App access to it, then move this code across.

## 3. Run it locally
```bash
# Backend (needs Python 3.12+, PostgreSQL)
cd backend
python -m venv .venv && . .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
set/export DJANGO_DEBUG=true DATABASE_URL=postgres://USER:PASS@localhost:5432/dayfello
python manage.py migrate
python manage.py seed            # demo data
python manage.py runserver 0.0.0.0:8000
python manage.py test api        # 14 tests

# App (needs Flutter SDK; Android Studio / Xcode for mobile)
cd app
flutter pub get
flutter run -d chrome                                                # web → http://localhost:8000
flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1       # Android emulator
flutter build apk --release --dart-define=API_BASE=https://api.YOURDOMAIN/api/v1
```
- **Demo logins** (password `Dayfello@123`): `admin` (admin), `+919876543210` (customer), `+919000010002` (Fellow "Meena Iyer").
- **Demo OTP** in dev: `123456`.
- **Ports:** Django runs on 8000. In production, put Nginx or Caddy in front on 443 with TLS, proxying to `127.0.0.1:8000` (gunicorn).

## 4. Configuration (environment variables)
| Variable | Purpose |
|---|---|
| `DJANGO_DEBUG`, `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS` | Core Django settings. Production needs DEBUG=false and a long secret. |
| `DATABASE_URL`, `DB_SSL_REQUIRE` | PostgreSQL connection |
| `CORS_ALLOWED_ORIGINS`, `CSRF_TRUSTED_ORIGINS` | Web app origin(s) |
| `JWT_ACCESS_MINUTES` (15), `JWT_REFRESH_DAYS` (7) | Token lifetimes |
| `DJANGO_ADMIN_PATH` | Secret path for Django admin |
| `DEMO_OTP` | Dev-only fixed OTP. **Leave empty in production.** |
| `SMS_PROVIDER` = `msg91` / `twilio` / `console` | OTP SMS. Set `MSG91_AUTH_KEY`, `MSG91_TEMPLATE_ID` or `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`. |
| `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` | Online payments. Webhook URL: `https://API/api/v1/payments/webhook/` (events `payment.captured`, `order.paid`). |
| `PAYMENTS_MOCK` | Defaults to DEBUG. When true and no Razorpay keys are set, online payments auto-confirm (no money moves). **Never true in production.** |
| `FIREBASE_CREDENTIALS` | Service-account JSON (path or raw) for push |
| App build defines | `API_BASE`, `MAP_TILE_URL`, and Firebase keys via `--dart-define-from-file=firebase.json` (template `app/firebase.example.json`) |

## 5. How key flows work
- **Booking lifecycle:** `awaiting_payment → pending → accepted → in_progress → completed`, or `cancelled` (by the customer) / `rejected` (by the Fellow).
  - `awaiting_payment` applies only to online (Razorpay) payments. The Fellow cannot see the booking until payment is verified.
  - Wallet and cash bookings start at `pending`.
- **Payments:**
  1. Creating a booking returns a `checkout` object.
  2. The app opens Razorpay checkout.
  3. The app posts the result to `/payments/verify/`; the backend checks the HMAC signature.
  4. The webhook is a backup confirmation. Each payment is applied exactly once.
  - Refunds on cancel or reject go back through Razorpay for online payments, and instantly to the wallet for wallet payments.
- **OTP login:**
  - `/auth/otp/request/` sends a 6-digit code. Only a hash of the code is stored.
  - Codes expire after 5 minutes, there is a 30-second cooldown between requests, and the code locks after 5 wrong tries.
  - The response is identical for unknown numbers, so the endpoint can't be used to check which numbers have accounts.
- **Live tracking:**
  - While an active job screen is open, the Fellow app posts GPS at most every 10 seconds.
  - The backend returns distance and ETA, and sends the customer one "arrived" alert when the Fellow is within 300 m.
- **Notifications:**
  - Every event creates an in-app record and, if configured, an FCM push.
  - Users can mute booking, arrival, payment or offers alerts. Emergency alerts can't be muted.

## 6. Status
### Done
- Customer, Fellow and admin apps; search, booking, wallet, coupons, ratings, chat, SOS, chatbot
- Maps: companion map, address pin picker, live tracking with ETA and arrival alert
- Push notifications (Firebase Cloud Messaging) with per-category preferences
- Security: HTTPS-only in production, JWT, role checks, rate limiting, upload checks
- Real SMS OTP login: backend (MSG91 or Twilio) and the app's "Send code" button
- Razorpay payments end to end: backend orders, verification, webhook and refunds; app checkout on Android and iOS (`razorpay_flutter`) and Web (checkout.js). If a customer abandons checkout, the booking is cancelled automatically.
- 14 backend tests and 2 Flutter tests passing
- Business deck: `dayfello_Bizentrix_Business_Presentation.pptx` (sent in chat; not in the repo)

### In progress
- Android release signing, app icon and splash, legal pages, Docker and CI (next up)

### Pending (launch blockers first)
1. Android release signing (`key.properties`) and iOS signing team and push capability
2. App icon and splash screen (still Flutter defaults)
3. Privacy policy and terms pages (drafts must be reviewed by a lawyer)
4. Dockerfile, docker-compose and CI (GitHub Actions running the tests)
5. Admin: view and verify uploaded Fellow documents; Fellow payouts and withdrawals
6. Real voice and video calls (Agora, Twilio or WebRTC), real-time chat, road routing and traffic ETA, background location
7. Translations (Tamil, Hindi, Telugu); an AI chatbot
8. Your accounts and keys: Firebase, Razorpay, MSG91 or Twilio (DLT template), map tile provider, server, domain and TLS
9. Deck: team and funding-ask slides; replace the proposed numbers with real ones

## 7. Known limitations
- Unpaid `awaiting_payment` bookings are not auto-expired yet. Add a periodic job to cancel them after about 30 minutes.
- Fellow location is shared only while the job screen is open.
- OpenStreetMap's public tile server is not allowed for production traffic. Set `MAP_TILE_URL`.

## Change log
### 2026-10-20 (2)
- App: a "Send code" button on OTP login; Razorpay checkout for bookings and wallet top-ups (Android, iOS, Web), verified by the backend before the booking reaches the Fellow. An unpaid checkout cancels the booking.
- Verified: Flutter analysis clean, 2 Flutter tests pass, web build compiles.

### 2026-10-20
- Added real SMS OTP login: request and verify endpoints, MSG91 or Twilio, hashed codes, expiry, cooldown and lockout.
- **Fixed:** wrong OTP attempts were rolled back along with the error, so the lockout never triggered. Attempts are now committed before the error is returned.
- Added Razorpay payments for bookings and wallet top-ups: orders, checkout signature verification, webhook (applied exactly once), and refunds through Razorpay. Booking gained the `awaiting_payment` status and a `payment_status` field. `PAYMENTS_MOCK` setting added.
- 4 new tests (14 in total).
- Renamed the app from Maitrio to **dayfello**: Android and iOS ID `app.dayfello.dayfello`, Flutter package `dayfello`; the companion role is now "Fellow"; demo password `Dayfello@123`.
- Created this handover document.

### 2026-10-14
- Built the Flutter app and the Django + PostgreSQL backend from the HTML demo.
- Added maps, live tracking, push notifications and notification preferences.
- Created the Bizentrix-theme business deck.

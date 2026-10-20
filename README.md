# dayfello — Companion booking platform

| Folder | What |
|---|---|
| `backend/` | Django + DRF REST API, PostgreSQL, JWT auth |
| `app/` | Flutter app (Android, iOS, Web): User, Partner and Admin experiences, chosen by the logged-in account's role |

## Backend

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # edit values, then export them (or use your host's env settings)
python manage.py migrate
python manage.py seed         # demo data; all demo passwords: Dayfello@123
python manage.py runserver    # dev only — use gunicorn in production:
gunicorn config.wsgi -b 0.0.0.0:8000 -w 3
```

Demo logins: `admin` (admin), `+919876543210` (user), `+919000010002` (partner "Meena Iyer").
Tests: `DJANGO_DEBUG=true python manage.py test api`.

### Security
- **Transport encryption:** with `DJANGO_DEBUG=false`, Django forces HTTPS (SSL redirect, HSTS with preload, secure cookies). Terminate TLS at your proxy (nginx/Caddy/load balancer) and forward `X-Forwarded-Proto`. Set `DB_SSL_REQUIRE=true` when Postgres is remote.
- **Auth:** JWT with 15‑minute access tokens and rotating 7‑day refresh tokens. Refresh tokens are blacklisted on rotation and on logout.
- **Authorization:** role checks (user/partner/admin). Each booking action is restricted to the right party (only the companion can accept, only the customer can cancel or rate). Chat is only allowed between users who share a booking.
- **Abuse limits:** throttling (10/min on auth endpoints, 60/min anonymous, 600/min authenticated), validated uploads (PDF/JPG/PNG ≤5MB), password validators, and a configurable Django-admin path.
- **App side:** the API base URL must be `https://` in release builds (loopback excepted for local testing). Tokens are stored in the Keychain/Keystore via `flutter_secure_storage`.

### API (prefix `/api/v1/`)
`auth/login|register|otp/verify|refresh|logout|me|change-password` · `services` · `companions` (+ `favorites`, `{id}/favorite`) ·
`bookings` (+ `{id}/cancel|accept|reject|check-in|check-out|location|rate`) · `wallet` · `coupons` · `notifications` (+ `mark-all-read`) ·
`devices` (push tokens) · `chat/{user_id}` · `sos` · `bot` · `cms` · `partner/dashboard` · `partner/docs` (+ `{id}/upload`) ·
`admin/stats|broadcast|users|companions|coupons|cms|flags|sos`

Booking lifecycle: `pending → accepted → in_progress → completed`, or `cancelled` (by the customer) / `rejected` (by the companion). Wallet payments are refunded automatically on cancel or reject.

## Flutter app

```bash
cd app
flutter pub get
flutter run -d chrome                                   # web, against http://localhost:8000
flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1   # Android emulator
flutter build apk|ipa|web --dart-define=API_BASE=https://api.yourdomain.com/api/v1
```

For the web build, add your web origin to `CORS_ALLOWED_ORIGINS` on the backend.

## Maps & live location
- Maps use `flutter_map` (OpenStreetMap tiles by default, no API key). OSM's public tile server is for light use only, so for production pass `--dart-define=MAP_TILE_URL=https://…/{z}/{x}/{y}.png?key=…` from a tile provider (MapTiler, Stadia, Mapbox…) and update the attribution in `lib/screens/maps.dart`.
- **Customers:** companions are sorted by real distance from the device (`/companions/?lat=&lng=&radius_km=`). Search has a map view. At booking time a map pin or the current location is saved as the service address (`dest_lat/dest_lng`).
- **Partners:** while an accepted or in-progress job is open, the app streams GPS to `bookings/{id}/location/` at most every 10s. The backend returns distance and ETA (25 km/h city estimate), and sends an "arrived" notification once the companion is within 300 m.
- Location is only shared while the job screen is open. Background tracking needs `geolocator` background mode plus the Android foreground-service and iOS "Always" permission.

## Notifications
- Every event creates an in-app notification. The badge refreshes on push or every 30s.
- **Categories:** booking, arrival, payment, offers, emergency. Users can mute any category except emergency under Profile → Notification settings. Muting is enforced on the server, so it applies to push as well.
- **Push (FCM)** is optional and switches on when configured:
  1. Create a Firebase project and add Android, iOS and Web apps.
  2. **Backend:** set `FIREBASE_CREDENTIALS` to the service-account JSON (a file path or the raw JSON).
  3. **App:** copy `app/firebase.example.json` to `app/firebase.json`, fill it in, and build with `--dart-define-from-file=firebase.json`.
  4. **Web:** copy `app/web/firebase-config.example.js` to `firebase-config.js` and fill it in. Create a Web Push certificate and set `FIREBASE_VAPID_KEY`.
  5. **iOS:** enable the Push Notifications capability in Xcode and upload an APNs key to Firebase.
- Tapping a push opens the related booking. Invalid tokens are pruned automatically.

## Still mocked / next integrations
- **Payments:** UPI, Card and Net Banking are recorded but not charged, and wallet top-up credits immediately. Integrate a gateway (Razorpay, Stripe…) and credit only from its verified webhook.
- **OTP:** `DEMO_OTP` stands in for SMS. Plug a provider into `OtpVerifyView`.
- **Voice/video calls:** UI only. Integrate Agora, Twilio or WebRTC, with call tokens issued by the backend.
- **Turn-by-turn routing:** the map draws a straight line; add a routing API (OSRM, Google Directions) for road routes and traffic-aware ETA.

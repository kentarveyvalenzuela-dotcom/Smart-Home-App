# BRIX - Smart Home IoT System

A complete IoT system with Flutter mobile/web frontend and Python FastAPI backend, featuring device control, sensor monitoring, Google OAuth authentication, and MQTT integration for ESP32 hardware communication.

## 🏗️ Project Structure

```
as_flutter_project/
├── lib/                    # Flutter app source code
│   ├── screens/            # UI screens
│   ├── services/           # Business logic & API services
│   ├── models/             # Data models
│   └── widgets/            # Reusable UI components
├── backend/                # Python FastAPI backend
│   ├── app/                # API routes & business logic
│   ├── .env                # Environment variables
│   └── requirements.txt    # Python dependencies
├── android/                # Android platform files
├── ios/                    # iOS platform files
├── web/                    # Web platform files
├── assets/                 # Images, icons, fonts
├── scripts/                # ESP32 firmware & utility scripts
└── test/                   # Flutter tests
```

## 🚀 Quick Start

### Prerequisites
- Flutter SDK (3.x+)
- Python 3.9+
- PostgreSQL database
- Google OAuth client ID (if enabling Google sign-in)
- MQTT broker (HiveMQ or similar)

### Backend Setup
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Flutter App Setup
```powershell
flutter pub get
flutter run -d chrome          # Web
flutter run -d windows         # Desktop
flutter run                    # Connected device/emulator
```

## 🔧 Configuration

### Environment Variables (project `.env` or `backend/.env`)
```env
DATABASE_URL=postgresql://username:password@localhost:5432/as_mqtt
SECRET_KEY=your_secret_key
GOOGLE_CLIENT_ID=your_web_oauth_client_id.apps.googleusercontent.com
MQTT_BROKER=your_mqtt_broker
MQTT_PORT=8883
```

The backend uses PostgreSQL. To import the existing local SQLite data once, configure `DATABASE_URL` and run from the project directory:

```powershell
python backend/migrate_sqlite_to_postgres.py
```

The import preserves user and device IDs and password hashes, checks that the PostgreSQL tables are empty, and leaves `backend/users.db` unchanged. For a new database, apply the SQL files in `backend/migrations/` in numeric order (`001` through `006`) using your PostgreSQL client. The API does not run database migrations automatically. On an existing database, apply any missing migrations before starting the corresponding feature.

### MQTT device control
Device control requests are published by the authenticated backend to `home/device/{mqtt_client_id}/set` on the same HiveMQ broker used by the ESP32. Rotate any credential that was committed or shared in the HiveMQ Cloud console first. Put the new broker settings only in the untracked `.env` and local `scripts/secrets.h`, then restart the API and reflash the ESP32. The web app does not connect directly to a public broker or contain MQTT credentials.

Opening the authenticated dashboard creates the account's energy device record once. The numeric database ID is shown in Energy Monitor and must be copied to `ENERGY_DEVICE_ID` in the firmware secrets file. For ESP32 builds, copy `scripts/secrets.h.example` to `scripts/secrets.h` and enter Wi-Fi, backend LAN URL, MQTT, energy-device ID, and device-ingest credentials there. `scripts/secrets.h` is ignored by Git. Rotate credentials that were previously present in tracked source files; changing these files does not invalidate credentials already exposed in Git history.

### PostgreSQL, Google OAuth, SMTP, and 2FA
Copy `backend/.env.example` to `backend/.env` and fill in the private values. The backend also reads the project `.env` as a fallback. Set `GOOGLE_CLIENT_ID` to the Web OAuth client ID in the backend environment, and pass that same public ID to Flutter with `--dart-define=GOOGLE_CLIENT_ID=your_web_client_id.apps.googleusercontent.com`. Register each Android/iOS app in the same Google Cloud OAuth project; Android credentials must include the app package name and signing SHA fingerprints. The server verifies Google ID tokens and requires a verified Google email.

For mail delivery, configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, and `EMAIL_FROM`; Gmail requires an App Password, not the account password. New email/password registrations require a verification code. Passwords are stored with salted scrypt hashes; existing unsalted SHA-256 hashes are verified at login and upgraded after a successful login without requiring a password reset. Email codes are stored hashed, expire after 10 minutes, and allow at most five failed attempts. Password reset tokens are stored hashed in PostgreSQL and expire after 30 minutes. Apply `backend/migrations/006_auth_email_2fa.sql` to existing databases before using these routes. Email verification, 2FA, and reset requests return a configuration error if SMTP is missing or delivery fails. Existing accounts are marked verified by the migration to avoid locking them out.

Sensor ingestion from ESP32 firmware also requires `DEVICE_INGEST_API_KEY` to match the value compiled into each device. Configure it in `backend/.env` and `scripts/secrets.h`. The app creates an Energy Monitor device for the signed-in account; copy its numeric device ID into `ENERGY_DEVICE_ID` in `scripts/secrets.h` before flashing the ESP32. The ID must be numeric and must belong to the account that should own the sensor history.

The API stores accounts, preferences, devices, readings, alerts, logs, and notifications in PostgreSQL. Without an ESP32, an authenticated user can create sensor readings at `POST /sensors/create` or energy readings at `POST /energy/readings`. Voltage/current readings use the configured thresholds; each out-of-range episode creates an alert and in-app notification, and returning to range resolves the open alert. Sensor history is available at `/sensors/all` and `/sensors/device/{device_id}`; energy history is at `/energy/history`. The authenticated routes also include `/alerts/list`, `/alerts/summary`, read/resolve, and clear operations. ESP32 firmware can post to `POST /ingest/energy?device_id=<registered-id>` and `POST /ingest/sensors?device_id=<registered-id>` using the `X-Device-API-Key` header; both routes require a registered Energy Monitor device and matching `DEVICE_INGEST_API_KEY` values in `backend/.env` and `scripts/secrets.h`.

Apply or rerun the idempotent migrations `backend/migrations/002_app_features.sql`, `backend/migrations/004_sensor_thresholds.sql`, and `backend/migrations/005_push_notifications.sql` on an existing database before using sensors, energy history, thresholds, or push tokens. The settings page stores account-backed voltage/current thresholds. Manual readings sent to `POST /sensors/create` exercise the same threshold evaluator that can later be connected to firmware ingestion.

### Push notifications (FCM)
For mobile push delivery, enable Firebase Cloud Messaging and configure a Firebase Admin service-account JSON in the API host's `FIREBASE_SERVICE_ACCOUNT_JSON` environment variable (in `backend/.env` for local development). Keep this private key out of the Flutter app and source control. Apply `backend/migrations/005_push_notifications.sql` so the backend can store device tokens.

Register an Android app in the same Firebase project with package name `com.astralminds`, then place its downloaded `google-services.json` at `android/app/google-services.json`. The Google services Gradle plugin is applied automatically when that file exists. Register an iOS app with bundle ID `com.astralminds`; in Xcode, enable Push Notifications and Background Modes > Remote notifications, then upload an APNs authentication key in Firebase Project settings > Cloud Messaging. The Flutter app requests notification permission and registers its FCM token after sign-in. Provide the Firebase client values from that same project at build time with `--dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...`; these are public client settings, unlike the Admin service-account JSON. User notification preferences suppress push delivery when notifications are turned off. Backend delivery failures are logged while database notifications remain available. Web push is not configured.

For local development, the Flutter app uses `http://10.0.2.2:8000` on Android (Android Emulator's address for the host computer) and `http://localhost:8000` on web/desktop. Start the API with `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000`. A physical Android phone must use the computer's LAN IP instead (for example, `http://192.168.x.x:8000`); set that URL in the app's backend settings and allow port 8000 through the computer's firewall. The Android emulator and phone must be able to reach the computer over the network.

## 🔌 ESP32 Hardware

ESP32 firmware files are located in `scripts/`:
- `esp32_mqtt.ino` - Main MQTT communication firmware
- `esp32_mqtt_production.ino` - Production-ready firmware
- `wifi_config_template.h` - WiFi configuration template

## 📱 Features

- **User Authentication**: Google OAuth, Email/Password
- **Device Management**: Add, configure, control IoT devices
- **Real-time Monitoring**: Live sensor data via MQTT
- **Alert System**: Automated notifications for thresholds
- **Appliance Presets**: Save and apply device configurations
- **Dark Mode**: System and manual theme switching

## 🛠️ Development

### Running Tests
```powershell
flutter test
```

### Building for Production
```powershell
flutter build apk --release       # Android
flutter build web --release       # Web
flutter build windows --release   # Windows
```

## 📄 License

This project is proprietary software.

## 👤 Author

BRIX Smart Home Team

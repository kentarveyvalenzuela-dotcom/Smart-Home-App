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

The import preserves user and device IDs and password hashes, checks that the PostgreSQL tables are empty, and leaves `backend/users.db` unchanged. The API creates its PostgreSQL tables from `backend/migrations/001_initial.sql` on startup.

### MQTT device control
Device control requests are published by the authenticated backend to `home/device/{mqtt_client_id}/set` on the same HiveMQ broker used by the ESP32. Rotate any credential that was committed or shared in the HiveMQ Cloud console first. Put the new broker settings only in the untracked `.env` and local `scripts/secrets.h`, then restart the API and reflash the ESP32. The web app does not connect directly to a public broker or contain MQTT credentials.

Opening the authenticated dashboard creates the energy device record once using `ENERGY_DEVICE_ID` (defaults to `admin`), matching the ID sent by both ESP32 sketches. For ESP32 builds, copy `scripts/secrets.h.example` to `scripts/secrets.h` and enter Wi-Fi, backend LAN URL, MQTT, energy-device ID, and device-ingest credentials there. `scripts/secrets.h` is ignored by Git. Rotate credentials that were previously present in tracked source files; changing these files does not invalidate credentials already exposed in Git history.

### PostgreSQL, Google OAuth, SMTP, and 2FA
Copy `backend/.env.example` to `backend/.env` and fill in the private values. The backend also reads the project `.env` as a fallback. Set `GOOGLE_CLIENT_ID` to the Web OAuth client ID in the backend environment, and pass that same public ID to Flutter with `--dart-define=GOOGLE_CLIENT_ID=your_web_client_id.apps.googleusercontent.com`. Register each Android/iOS app in the same Google Cloud OAuth project; Android credentials must include the app package name and signing SHA fingerprints. The server verifies Google ID tokens and requires a verified Google email.

For mail delivery, configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, and `EMAIL_FROM`; Gmail requires an App Password, not the account password. New email/password registrations require a verification code. Email codes are stored hashed, expire after 10 minutes, and allow at most five failed attempts. Password reset tokens are stored hashed in PostgreSQL and expire after 30 minutes. Apply `backend/migrations/006_auth_email_2fa.sql` to existing databases before using these routes. Email verification, 2FA, and reset requests return a configuration error if SMTP is missing or delivery fails. Existing accounts are marked verified by the migration to avoid locking them out.

Sensor ingestion from ESP32 firmware also requires `DEVICE_INGEST_API_KEY` to match the value compiled into each device.

The API stores accounts, preferences, devices, sensors, energy readings, alerts, logs, and notifications in PostgreSQL. ESP32 firmware sends energy history to `/ingest/energy` and sensor history batches to `/ingest/sensors`, both authenticated with `DEVICE_INGEST_API_KEY`. Sensor batches include voltage, total and per-channel current, power, and energy; PostgreSQL assigns a server timestamp when none is supplied. The app reads sensor history through the authenticated `/sensors/*` routes and polls the energy API for live dashboard values.

### Push notifications (FCM)
Apply `backend/migrations/005_push_notifications.sql` to the configured PostgreSQL database. Install the updated backend requirements and configure Firebase Admin credentials on the API host using `FIREBASE_SERVICE_ACCOUNT_JSON` (the service account JSON as a secret environment variable). Configure Firebase for the Flutter Android/iOS app with the matching Firebase project and generate the platform Firebase options; do not commit service-account credentials. The app registers its FCM token after authentication. The API continues storing in-app notifications when FCM credentials are absent; remote delivery then remains disabled. User notification preferences suppress push delivery when notifications are turned off.

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

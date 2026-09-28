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
- Firebase account (for authentication)
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

### Environment Variables (backend/.env)
```env
DATABASE_URL=your_database_url
SECRET_KEY=your_secret_key
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
MQTT_BROKER=your_mqtt_broker
MQTT_PORT=8883
```

### Firebase Setup
1. Create a Firebase project
2. Enable Google Sign-In authentication
3. Download `google-services.json` (Android) / `GoogleService-Info.plist` (iOS)
4. Update `firebase_options.dart` with your config

## 🔌 ESP32 Hardware

ESP32 firmware files are located in `scripts/`:
- `esp32_mqtt.ino` - Main MQTT communication firmware
- `esp32_mqtt_production.ino` - Production-ready firmware
- `esp32cam_upload.ino` - Camera module support
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

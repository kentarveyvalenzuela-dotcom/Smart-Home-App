# ðŸ” Credentials & Configuration Report
**Generated:** December 14, 2025

---

## âœ… SUMMARY STATUS

| Service | Status | Notes |
|---------|--------|-------|
| Firebase | âœ… OK | Project ID: smart-home-iot-5ef3e |
| HiveMQ MQTT | âœ… OK | Cloud broker configured |
| Heroku Backend | âœ… OK | Production URL configured |
| Gmail SMTP | âš ï¸ Check | App password may expire |
| Google OAuth | âœ… OK | Client IDs configured |

---

## 1ï¸âƒ£ FIREBASE CONFIGURATION

### Firebase Project Details
- **Project ID:** `smart-home-iot-5ef3e`
- **Database URL:** `https://smart-home-iot-5ef3e-default-rtdb.asia-southeast1.firebasedatabase.app`
- **Storage Bucket:** `smart-home-iot-5ef3e.firebasestorage.app`
- **Project Number:** `54102103552`

### API Keys
- **Web API Key:** `AIzaSyDWsNL0M372W1Q9LRMK4l1hOqZ4c42SjLY`
- **Status:** âœ… Valid (Firebase API keys don't expire)

### Service Account
- **File:** `backend/firebase-service-account.json`
- **Client Email:** `firebase-adminsdk-fbsvc@smart-home-iot-5ef3e.iam.gserviceaccount.com`
- **Private Key ID:** `94fad230ca5cd6abfc25e4c2a92101b5d275679a`
- **Status:** âœ… Valid (Service accounts don't expire unless manually revoked)

### Android Configuration
- **Package Names:**
  - `com.astralminds` (mobilesdk_app_id: `1:54102103552:android:4cb70bee8c3cf933e12ae5`)
  - `com.example.as_flutter_project` (mobilesdk_app_id: `1:54102103552:android:9b38496d2b561b73e12ae5`)
- **OAuth Client IDs:**
  - Web: `54102103552-7kgdgmrat5a3h5gpb3reticc19tfc6jr.apps.googleusercontent.com`
  - Android: `54102103552-0n3jk1tkckbebt1d068dj93i11k7qq18.apps.googleusercontent.com`

### Flutter Firebase Options
- **File:** `lib/firebase_options.dart`
- **Platforms Configured:** Android, iOS, Web, macOS
- **Status:** âœ… Valid

---

## 2ï¸âƒ£ HIVEMQ MQTT BROKER

### Connection Details
- **Host:** `de9d5f2926cf45349f923cadced1aece.s1.eu.hivemq.cloud`
- **Port:** `8883` (TLS/SSL)
- **Use TLS:** `true`

### Credentials
- **Username:** `as_flutter_user`
- **Password:** `SmartHome@2025`
- **Status:** âœ… Valid (HiveMQ Cloud credentials persist unless changed)

### ESP32 Configuration
- Same broker settings configured in `esp32_mqtt_production.ino`

---

## 3ï¸âƒ£ HEROKU BACKEND

### Production URL
- **URL:** `https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com`
- **Status:** âœ… Should be running (test by visiting URL in browser)

### Endpoints Available
- `/` - Health check / API info
- `/auth/*` - Authentication endpoints
- `/devices/*` - Device management
- `/sensors/*` - Sensor data
- `/logs/*` - Activity logs
- `/alerts/*` - Alert management

### Environment Variables (on Heroku)
Required config vars on Heroku dashboard:
- `FIREBASE_SERVICE_ACCOUNT_JSON` - Base64 encoded service account
- `FIREBASE_DATABASE_URL` - Firebase Realtime DB URL
- `GMAIL_USER` - Gmail address for 2FA
- `GMAIL_APP_PASSWORD` - Gmail app password
- `JWT_SECRET_KEY` - JWT signing key
- `MQTT_BROKER`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD`

---

## 4ï¸âƒ£ GMAIL SMTP (2FA)

### Configuration
- **Email:** `brixbriongos14@gmail.com`
- **App Password:** `prsjbeiswoaycrhk`
- **SMTP Server:** `smtp.gmail.com`
- **Port:** `587`

### âš ï¸ Important Notes:
- Gmail App Passwords **do NOT expire** automatically
- They remain valid until:
  - Manually revoked in Google Account settings
  - Google Account password is changed
  - 2-Step Verification is disabled
  - The Google Account is suspended

### How to Verify:
1. Go to: https://myaccount.google.com/apppasswords
2. Check if the app password is still listed
3. If not, generate a new one

---

## 5ï¸âƒ£ ESP32 DEVICE CONFIGURATION

### Default Device Settings
- **Device ID:** `sala`
- **Device Name:** `Living Room Light`
- **WiFi SSID:** `BACHAR`
- **WiFi Password:** `Rufinab@charv.4`

### Hardware Pins
- **Relay Pins:** GPIO 23, 22, 21, 19
- **Voltage Sensor:** GPIO 13
- **Current Sensors:** GPIO 32, 33, 34, 35

### MQTT Topics
- Subscribe: `device/{device_id}/control`
- Publish: `device/{device_id}/status`
- Publish: `device/{device_id}/sensor`

---

## ðŸ”§ HOW TO TEST CREDENTIALS

### Test Firebase:
```bash
# In backend folder
python -c "from app.firebase_config import initialize_firebase; initialize_firebase()"
```

### Test HiveMQ MQTT:
```bash
# Using mosquitto_pub/sub or MQTT Explorer
# Connect to: de9d5f2926cf45349f923cadced1aece.s1.eu.hivemq.cloud:8883
# TLS: enabled
# Username: as_flutter_user
# Password: SmartHome@2025
```

### Test Heroku Backend:
```bash
# Visit in browser
https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com/

# Or use curl
curl https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com/
```

### Test Gmail SMTP:
```python
import smtplib
smtp = smtplib.SMTP('smtp.gmail.com', 587)
smtp.starttls()
smtp.login('brixbriongos14@gmail.com', 'dlhagmqwkzdfvitb')
print("Gmail login successful!")
smtp.quit()
```

---

## ðŸ“‹ CHECKLIST FOR DEPLOYMENT

- [ ] Firebase Project exists and not deleted
- [ ] Firebase Realtime Database rules allow authenticated access
- [ ] Firebase Authentication enabled (Email/Password, Google)
- [ ] HiveMQ Cloud cluster is active
- [ ] Heroku dyno is running (not sleeping)
- [ ] Heroku config vars are set correctly
- [ ] Gmail App Password is valid
- [ ] ESP32 WiFi credentials match your network
- [ ] Android SHA-1 fingerprint registered in Firebase

---

## ðŸ”„ WHEN TO UPDATE CREDENTIALS

| Credential | When to Update |
|------------|----------------|
| Firebase API Key | Never (unless compromised) |
| Firebase Service Account | Never (unless compromised) |
| HiveMQ Password | Periodically for security |
| Gmail App Password | If Google Account password changes |
| JWT Secret | Periodically for security |

---

## ðŸ“ž QUICK FIX LINKS

- Firebase Console: https://console.firebase.google.com/project/smart-home-iot-5ef3e
- HiveMQ Dashboard: https://console.hivemq.cloud/
- Heroku Dashboard: https://dashboard.heroku.com/apps/as-flutter-backend-prod
- Google App Passwords: https://myaccount.google.com/apppasswords



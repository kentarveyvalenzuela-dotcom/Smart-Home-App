// ESP32 WiFi Configuration Generator
// Use this to generate the correct WiFi code for your devices

// ============================================
// CONFIGURATION SECTION - EDIT THESE VALUES
// ============================================

// Your WiFi Network Name (SSID)
#define WIFI_SSID "YOUR_WIFI_NAME_HERE"

// Your WiFi Password
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD_HERE"

// MQTT Broker Address (Production HiveMQ Cloud)
#define MQTT_SERVER "de9d5f2926cf45349f923cadced1aece.s1.eu.hivemq.cloud"
#define MQTT_PORT 8883  // TLS enabled
#define MQTT_USERNAME "as_flutter_user"
#define MQTT_PASSWORD "SmartHome@2025"

// Device Name (used in MQTT topics)
#define DEVICE_NAME "esp32_device_1"

// ============================================
// HOW TO USE THIS FILE:
// ============================================

/*
1. FIND YOUR WIFI NETWORK:
   - Look at your WiFi network on your computer/phone
   - Note the exact name (case-sensitive)
   - Replace "YOUR_WIFI_NAME_HERE" with your WiFi network name

2. FIND YOUR WIFI PASSWORD:
   - Get the WiFi password from your router/network settings
   - Replace "YOUR_WIFI_PASSWORD_HERE" with your password
   - Make sure it's exactly correct (spaces, uppercase, etc.)

3. UPDATE DEVICE NAME:
   - Change "esp32_device_1" to something unique (e.g., "bedroom_esp32", "kitchen_esp32")
   - This will appear in MQTT topics

4. SAVE THIS FILE:
   - Save as config.h in your sketch folder

5. INCLUDE IN YOUR SKETCH:
   Add this line at the top of your .ino file:
   #include "config.h"

6. EXAMPLE SETUP:

   If your WiFi network name is: "MyHomeWiFi"
   And password is: "password123"
   
   Change to:
   #define WIFI_SSID "MyHomeWiFi"
   #define WIFI_PASSWORD "password123"

IMPORTANT NOTES:
- WiFi network name and password are case-sensitive
- ESP32 only supports 2.4GHz WiFi (not 5GHz)
- Make sure WiFi is in range of ESP32
- Double-check for trailing spaces in credentials
*/

// ============================================
// EXAMPLE MQTT TOPICS THIS DEVICE WILL USE:
// ============================================

/*
With DEVICE_NAME = "esp32_device_1", topics will be:

Voltage Data:
  sensors/voltage/pin13

Current Data:
  sensors/amperage/pin32
  sensors/amperage/pin33
  sensors/amperage/pin34
  sensors/amperage/pin35

Status Topic:
  esp32_device_1/status

Control Topic (to receive commands):
  esp32_device_1/set

Configuration Topics (for dynamic pin mapping):
  home/device/esp32_device_1/pin
  home/device/esp32_device_1/status
*/
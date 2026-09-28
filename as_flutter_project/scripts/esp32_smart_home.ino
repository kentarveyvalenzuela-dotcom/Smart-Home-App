/*
 * ============================================================================
 * ESP32 SMART HOME - UNIFIED FIRMWARE
 * ============================================================================
 *
 * FEATURES:
 * - Device Control (Relay switching via MQTT)
 * - Energy Monitoring (ZMPT101B + SCT-013-030 x4)
 * - Firebase Real-time Database Integration
 * - HiveMQ Cloud MQTT (TLS/SSL)
 * - Auto-reconnect WiFi & MQTT
 *
 * ============================================================================
 *                           YOUR WIRING SETUP
 * ============================================================================
 *
 *     ZMPT101B (Voltage):
 *       VCC  -> 3.3V
 *       GND  -> GND
 *       OUT  -> GPIO13
 *
 *     SCT-013-030 x4 (Current, jack removed, 2 wires):
 *       Each SCT needs BIAS CIRCUIT (see diagram below)
 *       SCT #1 -> GPIO35
 *       SCT #2 -> GPIO34
 *       SCT #3 -> GPIO33
 *       SCT #4 -> GPIO32
 *
 *     RELAY (Device Control):
 *       Default device "admin" -> GPIO23
 *
 * ============================================================================
 *                      SCT-013 BIAS CIRCUIT (Per Sensor)
 * ============================================================================
 *
 *     3.3V ----+---- 10k ----+-----------> ESP32 ADC Pin (35/34/33/32)
 *              |             |
 *              |        SCT Wire 1
 *              |             |
 *              |        SCT Wire 2
 *              |             |
 *     GND  ----+---- 10k ----+
 *
 * ============================================================================
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <HTTPClient.h>
#include <EEPROM.h>
#include <math.h>

// ============================================================================
//                         CONFIGURATION - CHANGE THESE!
// ============================================================================

// WiFi Configuration
const char* ssid = "YOUR_WIFI_SSID";           // <- Change this!
const char* password = "YOUR_WIFI_PASSWORD";   // <- Change this!

// Firebase Configuration (for energy data)
const char* FIREBASE_HOST = "smart-home-iot-5ef3e-default-rtdb.asia-southeast1.firebasedatabase.app";
const char* USER_ID = "3B6ahiyGwHOcL6dtM70ZmirxakN2"; // Firebase User UID

// MQTT Broker Configuration (HiveMQ Cloud)
const char* mqtt_server = "de9d5f2926cf45349f923cadced1aece.s1.eu.hivemq.cloud";
const int mqtt_port = 8883;
const char* mqtt_username = "as_flutter_user";
const char* mqtt_password = "SmartHome@2025";

// ============================================================================
//                              PIN CONFIGURATION
// ============================================================================

// ZMPT101B Voltage Sensor
#define VOLTAGE_PIN         13    // GPIO13 for ZMPT101B

// SCT-013-030 Current Sensors (4 channels)
#define CURRENT_CH1_PIN     35    // GPIO35 - SCT #1
#define CURRENT_CH2_PIN     34    // GPIO34 - SCT #2
#define CURRENT_CH3_PIN     33    // GPIO33 - SCT #3
#define CURRENT_CH4_PIN     32    // GPIO32 - SCT #4

// Default Relay Pin
#define DEFAULT_RELAY_PIN   23    // GPIO23 for "admin" device

// ============================================================================
//                            CALIBRATION VALUES
// ============================================================================

// For ZMPT101B - Adjust based on your multimeter reading
#define VOLTAGE_CALIBRATION     133.0   // Calibration factor (adjusted for ~220V)

// For SCT-013-030 (30A with built-in burden resistor)
#define CURRENT_CALIBRATION     30.0    // 30A sensor

// ADC Settings
#define ADC_COUNTS              4096    // ESP32 12-bit ADC
#define ADC_REF                 3.3     // Reference voltage

// Sampling
#define SAMPLE_PERIOD           20      // 20ms = 1 cycle at 50Hz

// ============================================================================
//                            DEVICE CONFIGURATION
// ============================================================================

String device_id = "admin";
String device_name = "Smart Home Controller";

// Device Management
#define MAX_DEVICES 8
String devNames[MAX_DEVICES];
int devPins[MAX_DEVICES];
bool devUsed[MAX_DEVICES];
bool devStates[MAX_DEVICES];

// Relay polarity (false = active-low, true = active-high)
const bool relayActiveHigh = true;

// EEPROM
#define EEPROM_SIZE 512
#define DEVICE_ID_ADDR 0
#define DEVICE_ID_MAGIC 0xAB

// ============================================================================
//                               MQTT TOPICS
// ============================================================================

const char* controller_status_topic = "home/controller/status";
const char* sensor_status_topic = "sensors/status";

// ============================================================================
//                             GLOBAL VARIABLES
// ============================================================================

WiFiClientSecure espClient;
PubSubClient mqttClient(espClient);

// Timing
unsigned long lastReconnectAttempt = 0;
unsigned long reconnectDelayMs = 1000;
const unsigned long maxReconnectDelayMs = 30000;
unsigned long lastSensorRead = 0;
const unsigned long sensorInterval = 1000;  // Read sensors every 1 second
unsigned long lastFirebaseUpload = 0;
const unsigned long firebaseInterval = 5000; // Upload to Firebase every 5 seconds
unsigned long startTime = 0; // For timestamp calculation

// Energy Data
double voltage = 0.0;
double current_ch1 = 0.0, current_ch2 = 0.0, current_ch3 = 0.0, current_ch4 = 0.0;
double current_total = 0.0;
double power = 0.0;
double energy_kwh = 0.0;

// ============================================================================
//                           FUNCTION DECLARATIONS
// ============================================================================

// WiFi & MQTT
void setupWiFi();
bool connectMqtt();
void mqttCallback(char* topic, byte* payload, unsigned int length);

// Device Control
void handleDeviceCommand(const String &name, const String &msg);
int registerDevice(const String &name, int pin);
int findIndexByName(const String &name);
int getDefaultPinForDevice(const String &name);
void setDeviceState(int idx, bool turnOn);
void publishDeviceStatus(const String &name, bool isOn);

// Energy Monitoring
double readVoltageRMS();
double readCurrentRMS(int pin);
void readAllSensors();
void uploadToFirebase();
void uploadToMqtt();

// Utilities
void handleSerialCommands();
void loadDeviceIdFromEEPROM();
void saveDeviceIdToEEPROM(String id);
String getTimestamp();

// ============================================================================
//                                   SETUP
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("\n\n");
  Serial.println("============================================================");
  Serial.println("   ESP32 SMART HOME - Unified Firmware");
  Serial.println("   Device Control + Energy Monitoring");
  Serial.println("============================================================");

  // Record start time
  startTime = millis();

  // Initialize EEPROM
  EEPROM.begin(EEPROM_SIZE);
  loadDeviceIdFromEEPROM();
  Serial.print("[OK] Device ID: ");
  Serial.println(device_id);

  // Initialize device arrays with explicit values
  Serial.println("[DEBUG] Initializing device arrays...");
  for (int i = 0; i < MAX_DEVICES; i++) {
    devUsed[i] = false;
    devPins[i] = -1;  // Use -1 as "not set" value
    devNames[i] = "";
    devStates[i] = false;
  }
  Serial.println("[DEBUG] Device arrays initialized");

  // Register default devices (all relay pins)
  // IMPORTANT: These names MUST MATCH the mqtt_id in Flutter app's pinSlots!
  Serial.println("\n[DEBUG] Registering default devices...");
  registerDevice("sala", 23);     // GPIO23 - Living Room
  registerDevice("kwarto", 22);   // GPIO22 - Bedroom
  registerDevice("kusina", 21);   // GPIO21 - Kitchen
  registerDevice("banyo", 19);    // GPIO19 - Bathroom
  registerDevice("garahe", 18);   // GPIO18 - Garage
  registerDevice("labas", 17);    // GPIO17 - Outside

  // Print all registered devices for verification
  Serial.println("\n[DEBUG] === REGISTERED DEVICES ===");
  for (int i = 0; i < MAX_DEVICES; i++) {
    if (devUsed[i]) {
      Serial.print("[DEBUG] Slot ");
      Serial.print(i);
      Serial.print(": '");
      Serial.print(devNames[i]);
      Serial.print("' -> GPIO");
      Serial.println(devPins[i]);
    }
  }
  Serial.println("[DEBUG] ============================\n");

  // EXPLICIT GPIO23 INITIALIZATION (for debugging)
  Serial.println("\n[DEBUG] Explicitly initializing GPIO23...");
  pinMode(23, OUTPUT);
  digitalWrite(23, relayActiveHigh ? LOW : HIGH);  // Start OFF
  Serial.print("[DEBUG] GPIO23 set to: ");
  Serial.println(relayActiveHigh ? "LOW (OFF)" : "HIGH (OFF)");
  Serial.print("[DEBUG] relayActiveHigh = ");
  Serial.println(relayActiveHigh ? "true" : "false");

  // Test GPIO23 briefly
  Serial.println("[DEBUG] Testing GPIO23 - turning ON for 500ms...");
  digitalWrite(23, relayActiveHigh ? HIGH : LOW);  // ON
  delay(500);
  digitalWrite(23, relayActiveHigh ? LOW : HIGH);  // OFF
  Serial.println("[DEBUG] GPIO23 test complete");

  // Configure ADC
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Initialize sensor pins
  pinMode(VOLTAGE_PIN, INPUT);
  pinMode(CURRENT_CH1_PIN, INPUT);
  pinMode(CURRENT_CH2_PIN, INPUT);
  pinMode(CURRENT_CH3_PIN, INPUT);
  pinMode(CURRENT_CH4_PIN, INPUT);

  Serial.println("[OK] Hardware initialized");
  Serial.println("\n[PIN CONFIG]");
  Serial.print("   ZMPT101B (Voltage): GPIO"); Serial.println(VOLTAGE_PIN);
  Serial.print("   SCT #1 (Current):   GPIO"); Serial.println(CURRENT_CH1_PIN);
  Serial.print("   SCT #2 (Current):   GPIO"); Serial.println(CURRENT_CH2_PIN);
  Serial.print("   SCT #3 (Current):   GPIO"); Serial.println(CURRENT_CH3_PIN);
  Serial.print("   SCT #4 (Current):   GPIO"); Serial.println(CURRENT_CH4_PIN);
  Serial.print("   Relay (admin):      GPIO"); Serial.println(DEFAULT_RELAY_PIN);

  Serial.println("\n[SERIAL COMMANDS]");
  Serial.println("   SET_DEVICE:<name>  - Change device ID");
  Serial.println("   GET_DEVICE         - Show current device ID");
  Serial.println("   RESET              - Restart ESP32");
  Serial.println();

  // Setup secure MQTT
  espClient.setInsecure();
  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);

  // Connect to WiFi
  setupWiFi();

  Serial.println("\n============================================================");
  Serial.println("   [OK] Setup Complete! Starting main loop...");
  Serial.println("============================================================\n");
}

// ============================================================================
//                                 MAIN LOOP
// ============================================================================

void loop() {
  // Handle serial commands
  handleSerialCommands();

  // Periodic status print (every 30 seconds)
  static unsigned long lastStatusPrint = 0;
  if (millis() - lastStatusPrint > 30000) {
    lastStatusPrint = millis();
    Serial.println();
    Serial.println("========== ESP32 STATUS ==========");
    Serial.print("WiFi: ");
    Serial.println(WiFi.status() == WL_CONNECTED ? "CONNECTED" : "DISCONNECTED");
    Serial.print("MQTT: ");
    Serial.println(mqttClient.connected() ? "CONNECTED" : "DISCONNECTED");
    Serial.print("Uptime: ");
    Serial.print(millis() / 1000);
    Serial.println(" seconds");
    Serial.println("Waiting for MQTT messages...");
    Serial.println("==================================");
  }

  // Maintain MQTT connection
  if (!mqttClient.connected()) {
    if (millis() - lastReconnectAttempt > reconnectDelayMs) {
      lastReconnectAttempt = millis();
      if (connectMqtt()) {
        reconnectDelayMs = 1000;
      } else {
        reconnectDelayMs = min(reconnectDelayMs * 2, maxReconnectDelayMs);
        Serial.print("[MQTT] Will retry in ");
        Serial.print(reconnectDelayMs);
        Serial.println(" ms");
      }
    }
  } else {
    mqttClient.loop();
  }

  // Read sensors every 1 second
  if (millis() - lastSensorRead >= sensorInterval) {
    lastSensorRead = millis();
    readAllSensors();
    uploadToMqtt();
  }

  // Upload to Firebase every 5 seconds
  if (millis() - lastFirebaseUpload >= firebaseInterval) {
    lastFirebaseUpload = millis();
    uploadToFirebase();
  }

  // WiFi reconnection check
  static unsigned long lastWifiCheck = 0;
  if (millis() - lastWifiCheck > 10000) {
    lastWifiCheck = millis();
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("[WIFI] Disconnected. Reconnecting...");
      WiFi.disconnect();
      WiFi.begin(ssid, password);
    }
  }
}

// ============================================================================
//                               WiFi SETUP
// ============================================================================

void setupWiFi() {
  Serial.print("[WIFI] Connecting to '");
  Serial.print(ssid);
  Serial.println("'...");
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - start) < 20000) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WIFI] Connected!");
    Serial.print("  IP Address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n[WIFI] Connection failed. Will retry in loop.");
  }
}

// ============================================================================
//                             MQTT CONNECTION
// ============================================================================

bool connectMqtt() {
  if (WiFi.status() != WL_CONNECTED) return false;

  String clientId = "ESP32_" + String((uint32_t)ESP.getEfuseMac(), HEX);
  Serial.print("[MQTT] Connecting as ");
  Serial.print(clientId);
  Serial.println("...");

  if (mqttClient.connect(clientId.c_str(), mqtt_username, mqtt_password,
                         controller_status_topic, 1, true, "OFFLINE")) {
    Serial.println("[MQTT] Connected!");

    // Subscribe to device control topics
    mqttClient.subscribe("home/device/+/set", 1);
    mqttClient.subscribe("home/device/+/pin", 1);
    mqttClient.subscribe("home/device/+/state", 1);
    mqttClient.subscribe("home/device/+", 1);

    String controlTopic = "device/" + device_id + "/control";
    mqttClient.subscribe(controlTopic.c_str(), 1);

    Serial.println("[MQTT] Subscribed to device topics");

    // Publish online status
    mqttClient.publish(controller_status_topic, "ONLINE", true);
    mqttClient.publish(sensor_status_topic, "online", true);

    return true;
  } else {
    Serial.print("[MQTT] Failed, rc=");
    Serial.println(mqttClient.state());
    return false;
  }
}

// ============================================================================
//                            MQTT CALLBACK
// ============================================================================

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // IMMEDIATE DEBUG - Print raw message
  Serial.println();
  Serial.println("****** MQTT MESSAGE RECEIVED ******");
  Serial.print("Topic: ");
  Serial.println(topic);
  Serial.print("Payload (");
  Serial.print(length);
  Serial.print(" bytes): ");
  for (unsigned int i = 0; i < length; i++) {
    Serial.print((char)payload[i]);
  }
  Serial.println();
  Serial.println("***********************************");

  String msg = "";
  for (unsigned int i = 0; i < length; i++) {
    char c = (char)payload[i];
    if (c >= 32) msg += c;
  }
  msg.trim();
  msg.toUpperCase();

  Serial.print("[MQTT RX] ");
  Serial.print(topic);
  Serial.print(": ");
  Serial.println(msg);

  String t = String(topic);

  // Handle OLD format: device/<id>/control
  String oldControlTopic = "device/" + device_id + "/control";
  if (t == oldControlTopic) {
    int pinStart = msg.indexOf("\"PIN\":");
    int actionStart = msg.indexOf("\"ACTION\":");

    if (pinStart != -1 && actionStart != -1) {
      int pinEnd = msg.indexOf(",", pinStart);
      if (pinEnd == -1) pinEnd = msg.indexOf("}", pinStart);
      String pinStr = msg.substring(pinStart + 6, pinEnd);
      pinStr.trim();
      int pin = pinStr.toInt();

      int actionEnd = msg.indexOf("\"", actionStart + 10);
      String action = msg.substring(actionStart + 10, actionEnd);
      action.trim();

      bool turnOn = (action == "ON" || action == "1");

      Serial.print("[CONTROL] Pin ");
      Serial.print(pin);
      Serial.print(" -> ");
      Serial.println(turnOn ? "ON" : "OFF");

      pinMode(pin, OUTPUT);
      digitalWrite(pin, relayActiveHigh ? (turnOn ? HIGH : LOW) : (turnOn ? LOW : HIGH));

      // Publish to BOTH old and new format for compatibility
      String oldStatusTopic = "device/" + device_id + "/status";
      String newStatusTopic = "home/device/" + device_id + "/status";
      String newStateTopic = "home/device/" + device_id + "/state";
      mqttClient.publish(oldStatusTopic.c_str(), turnOn ? "ON" : "OFF", true);
      mqttClient.publish(newStatusTopic.c_str(), turnOn ? "ON" : "OFF", true);
      mqttClient.publish(newStateTopic.c_str(), turnOn ? "ON" : "OFF", true);
    }
    return;
  }

  // Handle NEW format: home/device/<name>/...
  const String prefix = "home/device/";
  if (t.startsWith(prefix)) {
    String rest = t.substring(prefix.length());
    int slash = rest.indexOf('/');

    if (slash == -1) {
      handleDeviceCommand(rest, msg);
    } else {
      String name = rest.substring(0, slash);
      String action = rest.substring(slash + 1);

      if (action == "set") {
        handleDeviceCommand(name, msg);
      } else if (action == "pin") {
        registerDevice(name, msg.toInt());
      }
    }
  }
}

// ============================================================================
//                           DEVICE MANAGEMENT
// ============================================================================

void handleDeviceCommand(const String &name, const String &msg) {
  Serial.print("[DEBUG] handleDeviceCommand: name='");
  Serial.print(name);
  Serial.print("', msg='");
  Serial.print(msg);
  Serial.println("'");

  int idx = findIndexByName(name);
  Serial.print("[DEBUG] findIndexByName returned: ");
  Serial.println(idx);

  if (idx == -1) {
    int defaultPin = getDefaultPinForDevice(name);
    Serial.print("[DEBUG] getDefaultPinForDevice returned: ");
    Serial.println(defaultPin);

    if (defaultPin != -1) {
      idx = registerDevice(name, defaultPin);
    } else {
      Serial.print("[WARN] Unknown device: ");
      Serial.println(name);
      return;
    }
  }

  if (idx != -1) {
    bool turnOn = (msg == "ON" || msg == "1" || msg == "TRUE" || msg == "HIGH");
    Serial.print("[DEBUG] turnOn = ");
    Serial.println(turnOn ? "true" : "false");

    setDeviceState(idx, turnOn);
    publishDeviceStatus(name, turnOn);
  }
}

int registerDevice(const String &name, int pin) {
  Serial.print("[DEBUG] registerDevice called: name='");
  Serial.print(name);
  Serial.print("', pin=");
  Serial.println(pin);

  if (pin < 0 || pin > 39) {
    Serial.println("[ERROR] Invalid pin number!");
    return -1;
  }

  int idx = findIndexByName(name);
  Serial.print("[DEBUG] findIndexByName returned: ");
  Serial.println(idx);

  if (idx == -1) {
    // Find empty slot
    for (int i = 0; i < MAX_DEVICES; i++) {
      if (!devUsed[i]) {
        idx = i;
        devUsed[i] = true;
        devNames[i] = name;
        devPins[i] = pin;
        devStates[i] = false;
        Serial.print("[DEBUG] Assigned to slot ");
        Serial.print(i);
        Serial.print(", devPins[");
        Serial.print(i);
        Serial.print("] = ");
        Serial.println(devPins[i]);
        break;
      }
    }
  } else {
    // Update existing device's pin
    devPins[idx] = pin;
    Serial.print("[DEBUG] Updated existing slot ");
    Serial.print(idx);
    Serial.print(", devPins[");
    Serial.print(idx);
    Serial.print("] = ");
    Serial.println(devPins[idx]);
  }

  if (idx != -1) {
    pinMode(pin, OUTPUT);
    digitalWrite(pin, relayActiveHigh ? LOW : HIGH); // Start OFF
    Serial.print("[OK] Registered '");
    Serial.print(name);
    Serial.print("' -> GPIO");
    Serial.print(pin);
    Serial.print(" (slot ");
    Serial.print(idx);
    Serial.println(")");

    // Verify the registration
    Serial.print("[VERIFY] devNames[");
    Serial.print(idx);
    Serial.print("] = '");
    Serial.print(devNames[idx]);
    Serial.print("', devPins[");
    Serial.print(idx);
    Serial.print("] = ");
    Serial.println(devPins[idx]);
  } else {
    Serial.println("[ERROR] No available slot for device!");
  }

  return idx;
}

int findIndexByName(const String &name) {
  Serial.print("[DEBUG] findIndexByName searching for: '");
  Serial.print(name);
  Serial.println("'");

  for (int i = 0; i < MAX_DEVICES; i++) {
    if (devUsed[i]) {
      Serial.print("[DEBUG]   Slot ");
      Serial.print(i);
      Serial.print(": name='");
      Serial.print(devNames[i]);
      Serial.print("', pin=");
      Serial.print(devPins[i]);
      if (devNames[i] == name) {
        Serial.println(" <- MATCH!");
        return i;
      }
      Serial.println();
    }
  }
  Serial.println("[DEBUG]   Not found, returning -1");
  return -1;
}

int getDefaultPinForDevice(const String &name) {
  // Map device names to GPIO pins
  // IMPORTANT: These names MUST MATCH the mqtt_id in Flutter app's pinSlots!

  // Filipino room names (PRIMARY - used by Flutter app)
  if (name == "sala") return 23;      // Living Room - GPIO23
  if (name == "kwarto") return 22;    // Bedroom - GPIO22
  if (name == "kusina") return 21;    // Kitchen - GPIO21
  if (name == "banyo") return 19;     // Bathroom - GPIO19
  if (name == "garahe") return 18;    // Garage - GPIO18
  if (name == "labas") return 17;     // Outside - GPIO17

  // English alternatives
  if (name == "living") return 23;
  if (name == "bedroom") return 22;
  if (name == "kitchen") return 21;
  if (name == "bathroom") return 19;
  if (name == "garage") return 18;
  if (name == "outside") return 17;

  // Generic relay names (backward compatibility)
  if (name == "relay1") return 23;
  if (name == "relay2") return 22;
  if (name == "relay3") return 21;
  if (name == "relay4") return 19;
  if (name == "relay5") return 18;
  if (name == "relay6") return 17;

  // Legacy names
  if (name == "admin") return 23;
  if (name == "app") return 21;
  if (name == "light1") return 22;
  if (name == "light2") return 19;
  if (name == "outlet1") return 18;
  if (name == "outlet2") return 17;

  return -1;
}

void setDeviceState(int idx, bool turnOn) {
  int pin = devPins[idx];

  // SAFETY CHECK: If pin is 0 or invalid, try to get the correct pin from defaults
  if (pin <= 0 || pin > 39) {
    Serial.print("[WARN] Invalid pin ");
    Serial.print(pin);
    Serial.print(" for device '");
    Serial.print(devNames[idx]);
    Serial.println("'. Attempting to fix...");

    // Try to get correct pin from defaults
    int correctPin = getDefaultPinForDevice(devNames[idx]);
    if (correctPin > 0) {
      devPins[idx] = correctPin;
      pin = correctPin;
      Serial.print("[FIX] Corrected pin to GPIO");
      Serial.println(pin);
    } else {
      Serial.println("[ERROR] Could not determine correct pin!");
      return;
    }
  }

  devStates[idx] = turnOn;

  // For active-low relays (most common): LOW = ON, HIGH = OFF
  // For active-high relays: HIGH = ON, LOW = OFF
  int pinValue = relayActiveHigh ? (turnOn ? HIGH : LOW) : (turnOn ? LOW : HIGH);

  Serial.print("[RELAY] Setting GPIO");
  Serial.print(pin);
  Serial.print(" to ");
  Serial.print(pinValue == HIGH ? "HIGH" : "LOW");
  Serial.print(" (relay ");
  Serial.print(turnOn ? "ON" : "OFF");
  Serial.println(")");

  // Ensure pin is set as output
  pinMode(pin, OUTPUT);
  digitalWrite(pin, pinValue);

  // Debug readback
  int readBack = digitalRead(pin);
  Serial.print("[DEBUG] GPIO");
  Serial.print(pin);
  Serial.print(" readback: ");
  Serial.println(readBack == HIGH ? "HIGH" : "LOW");

  Serial.print("[RELAY] ");
  Serial.print(devNames[idx]);
  Serial.print(" -> ");
  Serial.print(turnOn ? "ON" : "OFF");
  Serial.print(" (GPIO");
  Serial.print(pin);
  Serial.println(") DONE");
}

void publishDeviceStatus(const String &name, bool isOn) {
  const char* state = isOn ? "ON" : "OFF";

  String stateTopic = "home/device/" + name + "/state";
  String statusTopic = "home/device/" + name + "/status";

  mqttClient.publish(stateTopic.c_str(), state, true);
  mqttClient.publish(statusTopic.c_str(), state, true);
}

// ============================================================================
//                           ENERGY MONITORING
// ============================================================================

double readVoltageRMS() {
  double sumSquared = 0;
  int sampleCount = 0;
  unsigned long sampleStart = millis();

  while (millis() - sampleStart < SAMPLE_PERIOD) {
    int raw = analogRead(VOLTAGE_PIN);
    double sampleV = ((raw * ADC_REF) / ADC_COUNTS) - 1.65; // Center at 1.65V bias
    sumSquared += sampleV * sampleV;
    sampleCount++;
  }

  double vrms = sqrt(sumSquared / sampleCount);
  return vrms * VOLTAGE_CALIBRATION;
}

double readCurrentRMS(int pin) {
  double sumSquared = 0;
  int sampleCount = 0;
  unsigned long sampleStart = millis();

  while (millis() - sampleStart < SAMPLE_PERIOD) {
    int raw = analogRead(pin);
    double sampleI = ((raw * ADC_REF) / ADC_COUNTS) - 1.65; // Center at 1.65V bias
    sumSquared += sampleI * sampleI;
    sampleCount++;
  }

  double irms = sqrt(sumSquared / sampleCount);

  // SCT-013-030: 30A = 1V output with built-in burden
  return irms * CURRENT_CALIBRATION;
}

void readAllSensors() {
  // Read voltage
  voltage = readVoltageRMS();

  // Read all 4 current channels
  current_ch1 = readCurrentRMS(CURRENT_CH1_PIN);
  current_ch2 = readCurrentRMS(CURRENT_CH2_PIN);
  current_ch3 = readCurrentRMS(CURRENT_CH3_PIN);
  current_ch4 = readCurrentRMS(CURRENT_CH4_PIN);

  // Calculate totals
  current_total = current_ch1 + current_ch2 + current_ch3 + current_ch4;
  power = voltage * current_total;

  // Accumulate energy (power x time in hours)
  // Since we read every 1 second: energy += power x (1/3600) / 1000 kWh
  energy_kwh += power / 3600000.0;

  // Print to Serial
  Serial.println("----------------------------------------");
  Serial.print("Voltage: ");
  Serial.print(voltage, 1);
  Serial.println(" V");
  Serial.print("Current: CH1=");
  Serial.print(current_ch1, 2);
  Serial.print("A CH2=");
  Serial.print(current_ch2, 2);
  Serial.print("A CH3=");
  Serial.print(current_ch3, 2);
  Serial.print("A CH4=");
  Serial.print(current_ch4, 2);
  Serial.println("A");
  Serial.print("Total: ");
  Serial.print(current_total, 2);
  Serial.print(" A | Power: ");
  Serial.print(power, 1);
  Serial.print(" W | Energy: ");
  Serial.print(energy_kwh, 4);
  Serial.println(" kWh");
}

void uploadToMqtt() {
  if (!mqttClient.connected()) return;

  // Publish sensor data to MQTT
  mqttClient.publish("sensors/voltage/pin13", String(voltage, 2).c_str(), true);
  mqttClient.publish("sensors/current/ch1", String(current_ch1, 2).c_str(), true);
  mqttClient.publish("sensors/current/ch2", String(current_ch2, 2).c_str(), true);
  mqttClient.publish("sensors/current/ch3", String(current_ch3, 2).c_str(), true);
  mqttClient.publish("sensors/current/ch4", String(current_ch4, 2).c_str(), true);
  mqttClient.publish("sensors/current/total", String(current_total, 2).c_str(), true);
  mqttClient.publish("sensors/power", String(power, 2).c_str(), true);
  mqttClient.publish("sensors/energy", String(energy_kwh, 4).c_str(), true);
}

// Generate ISO 8601 timestamp string
String getTimestamp() {
  unsigned long uptime = millis() / 1000; // seconds since boot
  int hours = (uptime / 3600) % 24;
  int minutes = (uptime / 60) % 60;
  int seconds = uptime % 60;

  char buf[32];
  // Format: 2025-12-15T12:30:45Z (ISO 8601)
  sprintf(buf, "2025-12-15T%02d:%02d:%02dZ", hours, minutes, seconds);
  return String(buf);
}

void uploadToFirebase() {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;

  // Upload to Firebase Realtime Database
  String url = "https://" + String(FIREBASE_HOST) +
               "/users/" + String(USER_ID) +
               "/sensors/energy.json";

  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  // Create JSON payload - ALL VALUES AS PROPER TYPES
  // timestamp must be STRING for Flutter parsing
  String json = "{";
  json += "\"voltage\":" + String(voltage, 2) + ",";
  json += "\"current\":" + String(current_total, 2) + ",";
  json += "\"power\":" + String(power, 2) + ",";
  json += "\"energy\":" + String(energy_kwh, 4) + ",";
  json += "\"timestamp\":\"" + getTimestamp() + "\",";
  json += "\"uptime_ms\":" + String(millis()) + ",";
  json += "\"channels\":{";
  json += "\"ch1\":" + String(current_ch1, 2) + ",";
  json += "\"ch2\":" + String(current_ch2, 2) + ",";
  json += "\"ch3\":" + String(current_ch3, 2) + ",";
  json += "\"ch4\":" + String(current_ch4, 2);
  json += "}}";

  int httpCode = http.PUT(json);

  if (httpCode == HTTP_CODE_OK) {
    Serial.println("[FIREBASE] Upload OK");
  } else {
    Serial.print("[FIREBASE] Error: ");
    Serial.println(httpCode);
  }

  http.end();
}

// ============================================================================
//                            SERIAL COMMANDS
// ============================================================================

void handleSerialCommands() {
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();

    if (cmd.startsWith("SET_DEVICE:")) {
      String newId = cmd.substring(11);
      newId.trim();
      newId.toLowerCase();

      if (newId.length() > 0 && newId.length() < 32) {
        device_id = newId;
        saveDeviceIdToEEPROM(device_id);
        Serial.print("[OK] Device ID changed to: ");
        Serial.println(device_id);
        Serial.println("[WARN] Restart ESP32 for changes to take effect");
      }
    } else if (cmd == "GET_DEVICE") {
      Serial.print("Current Device ID: ");
      Serial.println(device_id);
    } else if (cmd == "RESET") {
      Serial.println("Restarting...");
      delay(500);
      ESP.restart();
    } else if (cmd.length() > 0) {
      Serial.println("Commands: SET_DEVICE:<id>, GET_DEVICE, RESET");
    }
  }
}

// ============================================================================
//                            EEPROM FUNCTIONS
// ============================================================================

void loadDeviceIdFromEEPROM() {
  if (EEPROM.read(DEVICE_ID_ADDR) == DEVICE_ID_MAGIC) {
    String savedId = "";
    for (int i = 1; i < 33; i++) {
      char c = EEPROM.read(DEVICE_ID_ADDR + i);
      if (c == 0) break;
      savedId += c;
    }
    if (savedId.length() > 0) {
      device_id = savedId;
      Serial.print("[OK] Loaded device_id from EEPROM: ");
      Serial.println(device_id);
    }
  }
}

void saveDeviceIdToEEPROM(String id) {
  EEPROM.write(DEVICE_ID_ADDR, DEVICE_ID_MAGIC);
  for (int i = 0; i < 32; i++) {
    EEPROM.write(DEVICE_ID_ADDR + 1 + i, i < id.length() ? id[i] : 0);
  }
  EEPROM.commit();
  Serial.println("[OK] Device ID saved to EEPROM");
}

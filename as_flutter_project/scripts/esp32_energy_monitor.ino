/*
 * ═══════════════════════════════════════════════════════════════════════════════
 *                    ESP32 ENERGY MONITOR - DETAILED WIRING DIAGRAM
 *                         ZMPT101B + SCT-013-030 (×4, No Jack)
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * YOUR SETUP:
 * - SCT-013-030: 30A, Built-in burden resistor, Jack removed (2 wires)
 * - ZMPT101B: Voltage sensor on GPIO 13
 * - SCT Pins: GPIO 35, 34, 33, 32
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                              MAIN WIRING DIAGRAM
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *     ┌─────────────────────────────────────────────────────────────────────────┐
 *     │                                                                         │
 *     │   AC MAINS 220V                                                         │
 *     │   ════════════                                                          │
 *     │        │                                                                │
 *     │        │                   ┌───────────────────────────────┐            │
 *     │   ┌────┴────┐              │          ESP32                │            │
 *     │   │ZMPT101B │              │                               │            │
 *     │   │ MODULE  │              │   ┌─────────────────────┐     │            │
 *     │   │         │              │   │                     │     │            │
 *     │   │  VCC ───┼──────────────┼───┤ 3.3V                │     │            │
 *     │   │  GND ───┼──────────────┼───┤ GND                 │     │            │
 *     │   │  OUT ───┼──────────────┼───┤ GPIO13 ◄── VOLTAGE  │     │            │
 *     │   │         │              │   │                     │     │            │
 *     │   └─────────┘              │   │ GPIO35 ◄── SCT #1   │     │            │
 *     │                            │   │ GPIO34 ◄── SCT #2   │     │            │
 *     │                            │   │ GPIO33 ◄── SCT #3   │     │            │
 *     │                            │   │ GPIO32 ◄── SCT #4   │     │            │
 *     │                            │   │                     │     │            │
 *     │                            │   └─────────────────────┘     │            │
 *     │                            │                               │            │
 *     │                            └───────────────────────────────┘            │
 *     │                                                                         │
 *     │   ┌────────────────────────────────────────────────────────┐            │
 *     │   │                    LOAD CIRCUITS                       │            │
 *     │   │                                                        │            │
 *     │   │   CIRCUIT 1        CIRCUIT 2       CIRCUIT 3      CIRCUIT 4        │
 *     │   │   (Kitchen)        (Living)        (Bedroom)      (Others)         │
 *     │   │      │                │                │              │            │
 *     │   │   ┌──┴──┐          ┌──┴──┐          ┌──┴──┐        ┌──┴──┐         │
 *     │   │   │LOAD │          │LOAD │          │LOAD │        │LOAD │         │
 *     │   │   │ #1  │          │ #2  │          │ #3  │        │ #4  │         │
 *     │   │   └──┬──┘          └──┬──┘          └──┬──┘        └──┬──┘         │
 *     │   │      │                │                │              │            │
 *     │   │   [SCT#1]          [SCT#2]          [SCT#3]        [SCT#4]         │
 *     │   │   GPIO35           GPIO34           GPIO33         GPIO32          │
 *     │   │                                                        │            │
 *     │   └────────────────────────────────────────────────────────┘            │
 *     │                                                                         │
 *     └─────────────────────────────────────────────────────────────────────────┘
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *               SCT-013-030 CONNECTION (Built-in Burden, No Jack)
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *     Dahil may BUILT-IN BURDEN RESISTOR na ang SCT-013-030, hindi na kailangan
 *     ng external 33Ω resistor. Pero kailangan pa rin ng BIAS CIRCUIT para
 *     i-center ang AC signal sa 1.65V (kalahati ng 3.3V).
 *
 *     ┌─────────────────────────────────────────────────────────────────────────┐
 *     │                                                                         │
 *     │   SCT-013-030                                                           │
 *     │   (Jack Removed)                                                        │
 *     │                                                                         │
 *     │      ┌──────────┐                                                       │
 *     │      │   ┌──┐   │        WIRE 1 (Any Color)                             │
 *     │      │   │CT│   ├────────────────────────┐                              │
 *     │      │   │  │   │                        │                              │
 *     │      │   └──┘   ├─────────┐              │                              │
 *     │      └──────────┘         │              │                              │
 *     │           │          WIRE 2 (Any Color)  │                              │
 *     │           │               │              │                              │
 *     │       CLAMP ON            │              │                              │
 *     │       ONE WIRE            │              │                              │
 *     │       (Live OR            │              │                              │
 *     │        Neutral)           │              │                              │
 *     │                           │              │                              │
 *     │                           ▼              ▼                              │
 *     │                                                                         │
 *     │           ┌───────────────────────────────────────┐                     │
 *     │           │         BIAS CIRCUIT                  │                     │
 *     │           │                                       │                     │
 *     │           │                                       │                     │
 *     │    3.3V ──┼───────┤ 10kΩ ├────┬──────────────────┼──► To ESP32 ADC     │
 *     │           │                   │                   │    (GPIO 35/34/33/32)
 *     │           │                   │                   │                     │
 *     │           │         SCT Wire 1┘     ┌─ SCT Wire 2 │                     │
 *     │           │                         │             │                     │
 *     │           │              ┌──────────┘             │                     │
 *     │           │              │                        │                     │
 *     │     GND ──┼───────┤ 10kΩ ├────┴───────────────────┼──► GND             │
 *     │           │                                       │                     │
 *     │           │                                       │                     │
 *     │           │     Optional: Add 10µF capacitor      │                     │
 *     │           │     between ADC pin and GND           │                     │
 *     │           │     for noise filtering               │                     │
 *     │           │                                       │                     │
 *     │           └───────────────────────────────────────┘                     │
 *     │                                                                         │
 *     └─────────────────────────────────────────────────────────────────────────┘
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                    DETAILED BIAS CIRCUIT FOR ALL 4 SCT SENSORS
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *                              ESP32 3.3V
 *                                  │
 *          ┌───────────────────────┼───────────────────────┐
 *          │                       │                       │
 *          │      ┌────────────────┼────────────────┐      │
 *          │      │                │                │      │
 *        10kΩ   10kΩ             10kΩ             10kΩ     │
 *          │      │                │                │      │
 *          │      │                │                │      │
 *          ├──────┼────────────────┼────────────────┼──────┤ 1.65V BIAS
 *          │      │                │                │      │
 *          │      │                │                │      │
 *       ┌──┴──┐┌──┴──┐          ┌──┴──┐          ┌──┴──┐   │
 *       │SCT 1││SCT 2│          │SCT 3│          │SCT 4│   │
 *       │Wire ││Wire │          │Wire │          │Wire │   │
 *       └──┬──┘└──┬──┘          └──┬──┘          └──┬──┘   │
 *          │      │                │                │      │
 *          │      │                │                │      │
 *          ▼      ▼                ▼                ▼      │
 *       GPIO35 GPIO34           GPIO33           GPIO32    │
 *                                                          │
 *          │      │                │                │      │
 *          │      │                │                │      │
 *        10kΩ   10kΩ             10kΩ             10kΩ     │
 *          │      │                │                │      │
 *          │      │                │                │      │
 *          └──────┴────────────────┴────────────────┴──────┘
 *                                  │
 *                                 GND
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                         ZMPT101B VOLTAGE SENSOR
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *     ┌─────────────────────────────────────────────────────────────────────────┐
 *     │                                                                         │
 *     │          ⚠️  WARNING: HIGH VOLTAGE! BE CAREFUL!  ⚠️                     │
 *     │                                                                         │
 *     │                                                                         │
 *     │         AC MAINS 220V                                                   │
 *     │         ═════════════                                                   │
 *     │              │                                                          │
 *     │              │         ┌──────────────────┐                             │
 *     │         LIVE─┼─────────┤                  │                             │
 *     │              │         │    ZMPT101B      │                             │
 *     │              │         │     MODULE       │                             │
 *     │      NEUTRAL─┼─────────┤                  │                             │
 *     │              │         │   VCC ───────────┼──────► ESP32 3.3V           │
 *     │              │         │   GND ───────────┼──────► ESP32 GND            │
 *     │              │         │   OUT ───────────┼──────► ESP32 GPIO13         │
 *     │              │         │                  │                             │
 *     │              │         └──────────────────┘                             │
 *     │              │                                                          │
 *     │              │                                                          │
 *     │              │     Note: ZMPT101B has built-in isolation                │
 *     │              │     Safe for ESP32 connection                            │
 *     │              │                                                          │
 *     └─────────────────────────────────────────────────────────────────────────┘
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                      COMPLETE BREADBOARD LAYOUT
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *     ┌─────────────────────────────────────────────────────────────────────────┐
 *     │                         BREADBOARD TOP VIEW                             │
 *     │                                                                         │
 *     │   + ─────────────────────────────────────────────────────────── + (3.3V)│
 *     │   │    │    │    │    │    │    │    │    │    │    │    │    │         │
 *     │   │   10k  10k  10k  10k                                       │         │
 *     │   │    │    │    │    │                                        │         │
 *     │   │    ├────┼────┼────┼───────────────────────────────────────┤ (BIAS)  │
 *     │   │    │    │    │    │                                        │         │
 *     │   │  SCT1 SCT2 SCT3 SCT4                                       │         │
 *     │   │  Wire Wire Wire Wire                                       │         │
 *     │   │    │    │    │    │                                        │         │
 *     │   │    │    │    │    │      ┌─────────────────────────┐       │         │
 *     │   │    │    │    │    │      │        ESP32            │       │         │
 *     │   │    │    │    │    │      │                         │       │         │
 *     │   ├────┼────┼────┼────┼──────┤ 3.3V                    │       │         │
 *     │   │    │    │    │    │      │                         │       │         │
 *     │   │    └────┼────┼────┼──────┤ GPIO35 (SCT#1)          │       │         │
 *     │   │         └────┼────┼──────┤ GPIO34 (SCT#2)          │       │         │
 *     │   │              └────┼──────┤ GPIO33 (SCT#3)          │       │         │
 *     │   │                   └──────┤ GPIO32 (SCT#4)          │       │         │
 *     │   │                          │                         │       │         │
 *     │   │    ┌─────────────────────┤ GPIO13 (ZMPT)           │       │         │
 *     │   │    │                     │                         │       │         │
 *     │   │    │                     │ GND                     │       │         │
 *     │   │    │                     │                         │       │         │
 *     │   │    │                     └─────────────────────────┘       │         │
 *     │   │    │                                                       │         │
 *     │   │    │    ZMPT101B                                           │         │
 *     │   │    │    ┌───────┐                                          │         │
 *     │   │    └────┤ OUT   │                                          │         │
 *     │   ├─────────┤ VCC   │                                          │         │
 *     │   │    ┌────┤ GND   │                                          │         │
 *     │   │    │    └───────┘                                          │         │
 *     │   │    │         │                                             │         │
 *     │   │    │         │                                             │         │
 *     │   │   10k  10k  10k  10k                                       │         │
 *     │   │    │    │    │    │                                        │         │
 *     │   │    │    │    │    │                                        │         │
 *     │   - ─────────────────────────────────────────────────────────── - (GND) │
 *     │                                                                         │
 *     └─────────────────────────────────────────────────────────────────────────┘
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                      SCT CLAMP PLACEMENT ON WIRE
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *     ┌─────────────────────────────────────────────────────────────────────────┐
 *     │                                                                         │
 *     │       ⚠️  IMPORTANT: Clamp around ONE WIRE only!  ⚠️                    │
 *     │                                                                         │
 *     │                                                                         │
 *     │       ✅ CORRECT:                    ❌ WRONG:                          │
 *     │                                                                         │
 *     │       ┌──────────┐                   ┌──────────┐                       │
 *     │       │   SCT    │                   │   SCT    │                       │
 *     │       │  ┌────┐  │                   │  ┌────┐  │                       │
 *     │       │  │ ▓▓ │  │                   │  │ ▓▓ │  │                       │
 *     │   ════╪══│ ▓▓ │══╪════           ════╪══│ ▓▓ │══╪════                   │
 *     │   LIVE│  │ ▓▓ │  │                   │  │ ▓▓ │  │BOTH                   │
 *     │       │  └────┘  │               ════╪══│ ▓▓ │══╪════                   │
 *     │       └──────────┘                   │  └────┘  │                       │
 *     │                                      └──────────┘                       │
 *     │       Only LIVE wire                                                    │
 *     │       passes through              Both wires = ZERO reading!            │
 *     │                                   (magnetic fields cancel)              │
 *     │                                                                         │
 *     │                                                                         │
 *     │       Same applies for:                                                 │
 *     │       - Extension cord (open it, clamp ONE wire)                        │
 *     │       - Appliance cord (open it, clamp ONE wire)                        │
 *     │       - Circuit breaker output (clamp the LIVE wire)                    │
 *     │                                                                         │
 *     └─────────────────────────────────────────────────────────────────────────┘
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                              PARTS LIST (YOUR SETUP)
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *     ┌──────────────────────────────────────────────────────────────┐
 *     │ Component                  │ Qty │ Notes                    │
 *     ├──────────────────────────────────────────────────────────────┤
 *     │ ESP32 DevKit               │  1  │ Any ESP32 board          │
 *     │ ZMPT101B Module            │  1  │ AC Voltage sensor        │
 *     │ SCT-013-030                │  4  │ 30A, jack removed        │
 *     │ 10kΩ Resistor              │  8  │ For voltage dividers     │
 *     │ 10µF Capacitor (Optional)  │  4  │ For noise filtering      │
 *     │ Breadboard                 │  1  │ For prototyping          │
 *     │ Jumper Wires               │ Many│ Various colors           │
 *     └──────────────────────────────────────────────────────────────┘
 *
 *     Note: Hindi na kailangan ng 33Ω burden resistor dahil
 *           built-in na sa SCT-013-030!
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                              PIN SUMMARY
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *     ┌─────────────────────────────────────────────────────────────┐
 *     │  ESP32 PIN   │  CONNECTED TO           │  FUNCTION          │
 *     ├─────────────────────────────────────────────────────────────┤
 *     │  3.3V        │  ZMPT VCC + Bias circuit│  Power supply      │
 *     │  GND         │  ZMPT GND + Bias circuit│  Ground            │
 *     │  GPIO13      │  ZMPT101B OUT           │  Voltage reading   │
 *     │  GPIO35      │  SCT #1 + Bias          │  Current CH1       │
 *     │  GPIO34      │  SCT #2 + Bias          │  Current CH2       │
 *     │  GPIO33      │  SCT #3 + Bias          │  Current CH3       │
 *     │  GPIO32      │  SCT #4 + Bias          │  Current CH4       │
 *     └─────────────────────────────────────────────────────────────┘
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <math.h>

// ==================== CONFIGURATION ====================
// WiFi Credentials
const char* ssid = "YOUR_WIFI_SSID";           // Change this!
const char* password = "YOUR_WIFI_PASSWORD";   // Change this!

// Firebase Configuration
const char* FIREBASE_HOST = "smart-home-iot-5ef3e-default-rtdb.asia-southeast1.firebasedatabase.app";
const char* FIREBASE_AUTH = "AIzaSyDWsNL0M372W1Q9LRMK4l1hOqZ4c42SjLY";
const char* USER_ID = "YOUR_FIREBASE_USER_ID"; // Get from Firebase Auth

// ==================== PIN DEFINITIONS (YOUR SETUP) ====================
#define ZMPT_PIN        13    // Voltage sensor (ZMPT101B) - GPIO13
#define SCT_CH1_PIN     35    // Current sensor 1 - GPIO35
#define SCT_CH2_PIN     34    // Current sensor 2 - GPIO34
#define SCT_CH3_PIN     33    // Current sensor 3 - GPIO33
#define SCT_CH4_PIN     32    // Current sensor 4 - GPIO32

// ==================== CALIBRATION VALUES ====================
// For SCT-013-030 with built-in burden resistor
// Output: 1V AC at 30A, so at 1A = 0.0333V
// With 1.65V bias, signal swings around 1.65V
#define VOLTAGE_CALIBRATION   311.0   // Adjust based on multimeter reading
#define CURRENT_CALIBRATION   30.0    // 30A sensor
#define ADC_COUNTS            4096    // ESP32 12-bit ADC
#define ADC_REF               3.3     // Reference voltage

// Sampling
#define SAMPLE_PERIOD         20      // 20ms = 1 cycle at 50Hz

// ==================== GLOBALS ====================
double voltage = 0.0;
double current_ch1 = 0.0, current_ch2 = 0.0, current_ch3 = 0.0, current_ch4 = 0.0;
double current_total = 0.0;
double power = 0.0;
double energy_kwh = 0.0;

unsigned long lastUpdate = 0;

// ==================== FUNCTION DECLARATIONS ====================
void setupWiFi();
double readVoltage();
double readCurrent(int pin);
void sendToFirebase();

// ==================== SETUP ====================
void setup() {
  Serial.begin(115200);
  Serial.println("\n========================================");
  Serial.println("ESP32 Energy Monitor");
  Serial.println("ZMPT101B (GPIO13) + SCT-013-030 x4");
  Serial.println("Pins: SCT=35,34,33,32 | ZMPT=13");
  Serial.println("========================================");

  // Configure ADC
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Connect to WiFi
  setupWiFi();

  Serial.println("Energy Monitor Ready!");
  Serial.println("========================================");
}

// ==================== LOOP ====================
void loop() {
  if (millis() - lastUpdate >= 1000) {
    lastUpdate = millis();

    // Read all sensors
    voltage = readVoltage();
    current_ch1 = readCurrent(SCT_CH1_PIN);
    current_ch2 = readCurrent(SCT_CH2_PIN);
    current_ch3 = readCurrent(SCT_CH3_PIN);
    current_ch4 = readCurrent(SCT_CH4_PIN);

    current_total = current_ch1 + current_ch2 + current_ch3 + current_ch4;
    power = voltage * current_total;
    energy_kwh += power / 3600000.0;

    // Print readings
    Serial.println("----------------------------------------");
    Serial.printf("Voltage: %.1f V\n", voltage);
    Serial.printf("CH1: %.2fA | CH2: %.2fA | CH3: %.2fA | CH4: %.2fA\n",
                  current_ch1, current_ch2, current_ch3, current_ch4);
    Serial.printf("Total: %.2f A | Power: %.1f W | Energy: %.4f kWh\n",
                  current_total, power, energy_kwh);

    sendToFirebase();
  }
}

// ==================== WIFI SETUP ====================
void setupWiFi() {
  Serial.print("Connecting to WiFi: ");
  Serial.println(ssid);

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected!");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nWiFi failed!");
  }
}

// ==================== READ VOLTAGE (ZMPT101B on GPIO13) ====================
double readVoltage() {
  double sumSquared = 0;
  int sampleCount = 0;
  unsigned long startTime = millis();

  while (millis() - startTime < SAMPLE_PERIOD) {
    int raw = analogRead(ZMPT_PIN);
    double sampleV = ((raw * ADC_REF) / ADC_COUNTS) - 1.65; // Center at 1.65V
    sumSquared += sampleV * sampleV;
    sampleCount++;
  }

  double vrms = sqrt(sumSquared / sampleCount);
  return vrms * VOLTAGE_CALIBRATION;
}

// ==================== READ CURRENT (SCT-013-030) ====================
double readCurrent(int pin) {
  double sumSquared = 0;
  int sampleCount = 0;
  unsigned long startTime = millis();

  while (millis() - startTime < SAMPLE_PERIOD) {
    int raw = analogRead(pin);
    double sampleI = ((raw * ADC_REF) / ADC_COUNTS) - 1.65; // Center at 1.65V
    sumSquared += sampleI * sampleI;
    sampleCount++;
  }

  double irms = sqrt(sumSquared / sampleCount);

  // SCT-013-030: 30A = 1V output
  // With voltage divider bias, adjust calibration as needed
  return irms * CURRENT_CALIBRATION;
}

// ==================== SEND TO FIREBASE ====================
void sendToFirebase() {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  String url = "https://" + String(FIREBASE_HOST) +
               "/users/" + String(USER_ID) +
               "/sensors/energy.json?auth=" + String(FIREBASE_AUTH);

  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  StaticJsonDocument<512> doc;
  doc["voltage"] = voltage;
  doc["current"] = current_total;
  doc["power"] = power;
  doc["energy"] = energy_kwh;
  doc["timestamp"] = millis();

  JsonObject channels = doc.createNestedObject("channels");
  channels["ch1"] = current_ch1;
  channels["ch2"] = current_ch2;
  channels["ch3"] = current_ch3;
  channels["ch4"] = current_ch4;

  String payload;
  serializeJson(doc, payload);

  int httpCode = http.PUT(payload);
  if (httpCode == HTTP_CODE_OK) {
    Serial.println("✓ Firebase OK");
  }

  http.end();
}


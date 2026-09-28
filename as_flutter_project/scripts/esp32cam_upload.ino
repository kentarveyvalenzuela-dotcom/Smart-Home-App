/*
 * ESP32-CAM Smart Home Camera - UNIFIED VERSION
 *
 * Features:
 * - Live MJPEG streaming at /stream
 * - Single capture at /capture
 * - SOFTWARE-BASED Motion Detection (Frame Comparison - NO PIR sensor needed!)
 * - IMMEDIATE motion clip upload (no waiting for midnight!)
 * - 24-hour timelapse snapshots (every 5 minutes)
 * - SD Card storage (optional, for backup)
 * - MQTT auto-announcement for app discovery
 * - Firebase/Backend upload
 *
 * Hardware: ESP32-CAM (AI Thinker) only - no additional sensors required!
 */

#include "esp_camera.h"
#include "FS.h"
#include "SD_MMC.h"
#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <EEPROM.h>

// ==================== CONFIGURATION ====================
// WiFi Credentials
const char* ssid = "YOTC-3B3726";
const char* password = "9e9fjf62";

// MQTT Configuration (HiveMQ Cloud)
const char* mqtt_server = "de9d5f2926cf45349f923cadced1aece.s1.eu.hivemq.cloud";
const int mqtt_port = 8883;
const char* mqtt_username = "as_flutter_user";
const char* mqtt_password = "SmartHome@2025";
const char* camera_announce_topic = "cameras/esp32-cam-1/status";
const char* camera_stream_topic = "cameras/esp32-cam-1/stream_url";

// Backend Configuration
const char* backend_upload = "https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com/camera/upload";
const char* device_id = "esp32-cam-1";

// Motion Detection Settings (SOFTWARE-BASED - no PIR sensor needed!)
#define MOTION_THRESHOLD         15000   // Pixel difference threshold (adjust as needed)
#define MOTION_SAMPLE_SIZE       1000    // Number of pixels to sample

// Recording Settings
#define TIMELAPSE_INTERVAL_MS    300000   // 5 minutes between timelapse
#define MOTION_CLIP_FRAMES       45       // 15 seconds at 3fps
#define MOTION_COOLDOWN_MS       5000     // 5 seconds between motion detections
#define CLEANUP_DAYS             7        // Delete files older than 7 days

// ==================== CAMERA PINS (AI Thinker) ====================
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

// ==================== GLOBALS ====================
WebServer server(80);
WiFiClientSecure espClient;
PubSubClient mqttClient(espClient);

// State
bool sdCardReady = false;
bool motionDetected = false;
bool isRecordingClip = false;
int clipFrameCount = 0;
String currentClipPath = "";
String currentDate = "";

// Timing
unsigned long lastTimelapseTime = 0;
unsigned long lastMotionTime = 0;
unsigned long lastMqttAnnounce = 0;
unsigned long lastMotionCheck = 0;
const unsigned long mqttAnnounceInterval = 30000;
const unsigned long motionCheckInterval = 500;  // Check motion every 500ms

// Motion Detection (software-based using frame comparison)
uint8_t* prevFrameBuffer = NULL;
size_t prevFrameLen = 0;
bool motionEnabled = true;

// ==================== SETUP ====================
void setup() {
  Serial.begin(115200);

  Serial.println();
  Serial.println("================================================");
  Serial.println("  ESP32-CAM Smart Home - UNIFIED VERSION");
  Serial.println("  Motion Detection: SOFTWARE (Frame Comparison)");
  Serial.println("================================================");

  // Initialize Camera
  setupCamera();

  // Initialize SD Card (optional)
  setupSD();

  // Connect to WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print('.');
    delay(500);
  }
  Serial.println();
  Serial.print("[OK] Connected, IP: ");
  Serial.println(WiFi.localIP());

  // Sync time (GMT+8 Philippines)
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Synchronizing time");
  struct tm timeinfo;
  int retries = 0;
  while(!getLocalTime(&timeinfo) && retries < 10) {
    Serial.print(".");
    delay(1000);
    retries++;
  }
  if(getLocalTime(&timeinfo)){
    Serial.println("\n[OK] Time synchronized!");
    currentDate = getDateString();
    createDailyFolders();
  }

  // Setup MQTT
  espClient.setInsecure();
  mqttClient.setServer(mqtt_server, mqtt_port);
  connectMqtt();

  // Setup Web Server
  setupServer();

  // Announce camera
  announceCameraToMqtt();

  Serial.println("================================================");
  Serial.println("[OK] ESP32-CAM Ready!");
  Serial.print("[OK] Stream: http://");
  Serial.print(WiFi.localIP());
  Serial.println("/stream");
  Serial.println("================================================");
}

// ==================== CAMERA SETUP ====================
void setupCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 10;
  config.fb_count = 2;

  if(psramFound()){
    config.frame_size = FRAMESIZE_VGA;
    config.jpeg_quality = 10;
    config.fb_count = 2;
    Serial.println("[OK] PSRAM found, using VGA");
  } else {
    config.frame_size = FRAMESIZE_QVGA;
    config.jpeg_quality = 12;
    config.fb_count = 1;
    Serial.println("[WARN] No PSRAM, using QVGA");
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("[ERROR] Camera init failed: 0x%x\n", err);
    ESP.restart();
  }
  Serial.println("[OK] Camera initialized");
}

// ==================== SD CARD SETUP ====================
void setupSD() {
  if (!SD_MMC.begin("/sdcard", true)) {
    Serial.println("[WARN] SD Card not available - using backend only");
    sdCardReady = false;
    return;
  }

  uint8_t cardType = SD_MMC.cardType();
  if (cardType == CARD_NONE) {
    Serial.println("[WARN] No SD Card inserted");
    sdCardReady = false;
    return;
  }

  Serial.printf("[OK] SD Card: %lluMB\n", SD_MMC.cardSize() / (1024 * 1024));
  SD_MMC.mkdir("/timelapse");
  SD_MMC.mkdir("/motion_clips");
  sdCardReady = true;
}

// ==================== DATE/TIME HELPERS ====================
String getDateString() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return "";
  char buf[12];
  strftime(buf, sizeof(buf), "%Y-%m-%d", &timeinfo);
  return String(buf);
}

String getTimeString() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return String(millis());
  char buf[10];
  strftime(buf, sizeof(buf), "%H-%M-%S", &timeinfo);
  return String(buf);
}

void createDailyFolders() {
  if (!sdCardReady || currentDate.length() == 0) return;
  SD_MMC.mkdir(("/timelapse/" + currentDate).c_str());
  SD_MMC.mkdir(("/motion_clips/" + currentDate).c_str());
  Serial.println("[OK] Created folders for " + currentDate);
}

// ==================== MQTT ====================
void connectMqtt() {
  if (mqttClient.connected()) return;

  Serial.print("Connecting to MQTT...");
  String clientId = "ESP32CAM_" + String((uint32_t)ESP.getEfuseMac(), HEX);

  if (mqttClient.connect(clientId.c_str(), mqtt_username, mqtt_password)) {
    Serial.println(" connected!");
  } else {
    Serial.printf(" failed (rc=%d)\n", mqttClient.state());
  }
}

void announceCameraToMqtt() {
  if (!mqttClient.connected()) connectMqtt();
  if (!mqttClient.connected()) return;

  String streamUrl = "http://" + WiFi.localIP().toString() + "/stream";
  String cameraInfo = "{";
  cameraInfo += "\"device_id\":\"" + String(device_id) + "\",";
  cameraInfo += "\"name\":\"ESP32 Camera\",";
  cameraInfo += "\"stream_url\":\"" + streamUrl + "\",";
  cameraInfo += "\"capture_url\":\"http://" + WiFi.localIP().toString() + "/capture\",";
  cameraInfo += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
  cameraInfo += "\"sd_card\":" + String(sdCardReady ? "true" : "false") + ",";
  cameraInfo += "\"status\":\"online\"";
  cameraInfo += "}";

  mqttClient.publish(camera_announce_topic, cameraInfo.c_str(), true);
  mqttClient.publish(camera_stream_topic, streamUrl.c_str(), true);
  Serial.println("[MQTT] Camera announced");
}

// ==================== UPLOAD TO BACKEND ====================
void uploadToBackend(camera_fb_t* fb, bool isMotion) {
  if (!fb || WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  http.begin(backend_upload);
  http.addHeader("Content-Type", "image/jpeg");
  http.addHeader("X-Device-ID", device_id);
  http.addHeader("X-Event-Type", isMotion ? "motion" : "timelapse");
  http.addHeader("X-Timestamp", getTimeString());
  http.setTimeout(10000);

  int httpCode = http.POST(fb->buf, fb->len);

  if (httpCode == 200 || httpCode == 201) {
    Serial.printf("[UPLOAD] Success (%s)\n", isMotion ? "motion" : "timelapse");
  } else {
    Serial.printf("[UPLOAD] Failed: %d\n", httpCode);
  }
  http.end();
}

// ==================== SAVE TO SD CARD ====================
void saveToSD(camera_fb_t* fb, String folder, String filename) {
  if (!sdCardReady || !fb) return;

  String path = "/" + folder + "/" + currentDate + "/" + filename + ".jpg";
  File file = SD_MMC.open(path.c_str(), FILE_WRITE);
  if (file) {
    file.write(fb->buf, fb->len);
    file.close();
    Serial.println("[SD] Saved: " + path);
  }
}

// ==================== TIMELAPSE ====================
void captureTimelapse() {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) return;

  String time = getTimeString();

  // Save to SD
  saveToSD(fb, "timelapse", time);

  // Upload to backend
  uploadToBackend(fb, false);

  esp_camera_fb_return(fb);
  Serial.println("[TIMELAPSE] Captured: " + time);
}

// ==================== SOFTWARE MOTION DETECTION ====================
bool detectMotion(camera_fb_t* fb) {
  if (!fb || !motionEnabled) return false;

  // First frame - just save it
  if (prevFrameBuffer == NULL) {
    prevFrameBuffer = (uint8_t*)malloc(fb->len);
    if (prevFrameBuffer) {
      memcpy(prevFrameBuffer, fb->buf, fb->len);
      prevFrameLen = fb->len;
    }
    return false;
  }

  // Frame size changed - reallocate
  if (prevFrameLen != fb->len) {
    free(prevFrameBuffer);
    prevFrameBuffer = (uint8_t*)malloc(fb->len);
    if (prevFrameBuffer) {
      memcpy(prevFrameBuffer, fb->buf, fb->len);
      prevFrameLen = fb->len;
    }
    return false;
  }

  // Calculate difference between frames
  long diff = 0;
  int step = fb->len / MOTION_SAMPLE_SIZE;
  if (step < 1) step = 1;

  for (size_t i = 0; i < fb->len; i += step) {
    diff += abs((int)fb->buf[i] - (int)prevFrameBuffer[i]);
  }

  // Update previous frame
  memcpy(prevFrameBuffer, fb->buf, fb->len);

  // Check if motion detected
  bool hasMotion = (diff > MOTION_THRESHOLD);

  if (hasMotion) {
    Serial.printf("[MOTION] Detected! Diff: %ld (threshold: %d)\n", diff, MOTION_THRESHOLD);
  }

  return hasMotion;
}

// Check for motion using camera frames
void checkMotion() {
  if (millis() - lastMotionCheck < motionCheckInterval) return;
  lastMotionCheck = millis();

  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) return;

  bool hasMotion = detectMotion(fb);

  if (hasMotion) {
    handleMotionDetected(fb);
  }

  esp_camera_fb_return(fb);
}

// ==================== MOTION DETECTION & IMMEDIATE UPLOAD ====================
void handleMotionDetected(camera_fb_t* fb) {
  if (millis() - lastMotionTime < MOTION_COOLDOWN_MS) return;
  lastMotionTime = millis();

  Serial.println("[MOTION] Capturing and uploading immediately...");

  String time = getTimeString();

  // Save to SD
  saveToSD(fb, "motion_clips", time);

  // Upload to backend IMMEDIATELY (no waiting!)
  uploadToBackend(fb, true);

  // Notify via MQTT
  if (mqttClient.connected()) {
    String msg = "{\"event\":\"motion\",\"time\":\"" + time + "\",\"device\":\"" + device_id + "\"}";
    mqttClient.publish("cameras/esp32-cam-1/motion", msg.c_str());
  }
}

// ==================== WEB SERVER ====================
void setupServer() {
  server.on("/", HTTP_GET, handleRoot);
  server.on("/capture", HTTP_GET, handleCapture);
  server.on("/stream", HTTP_GET, handleStream);
  server.on("/status", HTTP_GET, handleStatus);
  server.begin();
  Serial.println("[OK] Web server started");
}

void handleRoot() {
  String html = "<!DOCTYPE html><html><head><title>ESP32-CAM</title>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;text-align:center;background:#1a1a2e;color:white;}";
  html += "h1{color:#00ff88;}.btn{padding:15px 30px;margin:10px;font-size:16px;";
  html += "background:#00ff88;border:none;border-radius:10px;cursor:pointer;}</style></head>";
  html += "<body><h1>ESP32-CAM Smart Home</h1>";
  html += "<p>Device: " + String(device_id) + "</p>";
  html += "<p>SD Card: " + String(sdCardReady ? "Ready" : "Not available") + "</p>";
  html += "<img src='/stream' style='max-width:100%;border-radius:10px;'><br>";
  html += "<a href='/capture'><button class='btn'>Capture Photo</button></a>";
  html += "<a href='/status'><button class='btn'>Status</button></a>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

void handleCapture() {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    server.send(500, "text/plain", "Camera capture failed");
    return;
  }
  server.sendHeader("Content-Type", "image/jpeg");
  server.sendHeader("Content-Length", String(fb->len));
  server.send(200, "image/jpeg", (const char*)fb->buf, fb->len);
  esp_camera_fb_return(fb);
}

void handleStream() {
  WiFiClient client = server.client();

  String response = "HTTP/1.1 200 OK\r\n";
  response += "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n";
  server.sendContent(response);

  while (client.connected()) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) break;

    client.printf("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n", fb->len);
    client.write(fb->buf, fb->len);
    client.print("\r\n");

    esp_camera_fb_return(fb);
    delay(100); // ~10 FPS
  }
}

void handleStatus() {
  String json = "{";
  json += "\"device_id\":\"" + String(device_id) + "\",";
  json += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
  json += "\"wifi_rssi\":" + String(WiFi.RSSI()) + ",";
  json += "\"sd_card\":" + String(sdCardReady ? "true" : "false") + ",";
  json += "\"uptime_ms\":" + String(millis()) + ",";
  json += "\"free_heap\":" + String(ESP.getFreeHeap()) + ",";
  json += "\"status\":\"online\"";
  json += "}";
  server.send(200, "application/json", json);
}

// ==================== MAIN LOOP ====================
void loop() {
  // Maintain MQTT connection
  if (!mqttClient.connected()) connectMqtt();
  mqttClient.loop();

  // Re-announce camera periodically
  if (millis() - lastMqttAnnounce >= mqttAnnounceInterval) {
    announceCameraToMqtt();
    lastMqttAnnounce = millis();
  }

  // Check for new day
  String today = getDateString();
  if (today.length() > 0 && today != currentDate) {
    Serial.println("[INFO] New day: " + today);
    currentDate = today;
    createDailyFolders();
  }

  // Timelapse capture (every 5 minutes)
  if (millis() - lastTimelapseTime >= TIMELAPSE_INTERVAL_MS) {
    captureTimelapse();
    lastTimelapseTime = millis();
  }

  // Handle web requests
  server.handleClient();

  // Software-based motion detection (using frame comparison)
  checkMotion();

  delay(10);
}


/*
 * Nuclear Alert ESP32 Client
 * ──────────────────────────────────────────────────────────────────────────────
 * Polls data/status.json from GitHub every 5 minutes.
 * Activates a servo on pin SERVO_PIN when status == "CONFIRMED".
 * Activates a buzzer on pin BUZZER_PIN as an audio alert.
 *
 * Libraries required (install via Arduino Library Manager):
 *   - ArduinoJson  (Benoit Blanchon)
 *   - ESP32Servo   (Kevin Harrington)
 *
 * ──────────────────────────────────────────────────────────────────────────────
 * CONFIGURATION — edit these before flashing:
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>

// ── WiFi ───────────────────────────────────────────────────────────────────────
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// ── Status JSON URL ────────────────────────────────────────────────────────────
// Replace YOUR_GITHUB_USER and YOUR_REPO_NAME
const char* STATUS_URL =
  "https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO_NAME/main/data/status.json";

// ── Pin definitions ────────────────────────────────────────────────────────────
const int SERVO_PIN  = 18;   // GPIO18 — change to your servo signal pin
const int BUZZER_PIN = 19;   // GPIO19 — change to your buzzer pin
const int LED_RED    = 2;    // Built-in LED or external red LED

// ── Polling interval (ms) ─────────────────────────────────────────────────────
const unsigned long POLL_INTERVAL_MS = 5UL * 60UL * 1000UL;  // 5 minutes

// ── Servo positions ────────────────────────────────────────────────────────────
const int SERVO_IDLE    = 0;    // degrees when idle
const int SERVO_ALERT   = 90;   // degrees when alert is active

// ── Globals ───────────────────────────────────────────────────────────────────
Servo alertServo;
unsigned long lastPoll = 0;
String currentStatus = "NONE";

// ──────────────────────────────────────────────────────────────────────────────
// WiFi connection helper
// ──────────────────────────────────────────────────────────────────────────────
void connectWiFi() {
  Serial.print("[WiFi] Connecting to ");
  Serial.println(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start > 15000) {
      Serial.println("[WiFi] Connection timeout. Restarting...");
      ESP.restart();
    }
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.print("[WiFi] Connected. IP: ");
  Serial.println(WiFi.localIP());
}

// ──────────────────────────────────────────────────────────────────────────────
// Fetch and parse status.json from GitHub
// Returns the status string ("NONE" | "SUSPECTED" | "CONFIRMED")
// or an empty string on error.
// ──────────────────────────────────────────────────────────────────────────────
String fetchStatus() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[HTTP] WiFi not connected. Reconnecting...");
    connectWiFi();
  }

  HTTPClient http;
  http.begin(STATUS_URL);
  http.setTimeout(10000);

  int httpCode = http.GET();

  if (httpCode != HTTP_CODE_OK) {
    Serial.printf("[HTTP] Request failed. Code: %d\n", httpCode);
    http.end();
    return "";
  }

  String payload = http.getString();
  http.end();

  // Parse JSON
  StaticJsonDocument<512> doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) {
    Serial.print("[JSON] Parse error: ");
    Serial.println(err.c_str());
    return "";
  }

  const char* status = doc["status"] | "NONE";
  float confidence   = doc["confidence"] | 0.0f;

  Serial.printf("[Status] %s (confidence: %.2f)\n", status, confidence);
  return String(status);
}

// ──────────────────────────────────────────────────────────────────────────────
// Alert activation — servo + buzzer + LED
// ──────────────────────────────────────────────────────────────────────────────
void activateAlert() {
  Serial.println("[ALERT] *** CONFIRMED NUCLEAR EVENT — ACTIVATING ALERT ***");
  digitalWrite(LED_RED, HIGH);

  // Move servo to alert position
  alertServo.write(SERVO_ALERT);

  // Buzzer pattern: 3 long beeps
  for (int i = 0; i < 3; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    delay(800);
    digitalWrite(BUZZER_PIN, LOW);
    delay(300);
  }
}

void deactivateAlert() {
  Serial.println("[Alert] Status is not CONFIRMED. Idle.");
  alertServo.write(SERVO_IDLE);
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_RED, LOW);
}

// ──────────────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println("[Boot] Nuclear Alert ESP32 starting...");

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_RED, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_RED, LOW);

  alertServo.attach(SERVO_PIN);
  alertServo.write(SERVO_IDLE);

  connectWiFi();

  // Poll immediately on boot
  currentStatus = fetchStatus();
  if (currentStatus == "CONFIRMED") {
    activateAlert();
  }

  lastPoll = millis();
}

// ──────────────────────────────────────────────────────────────────────────────
void loop() {
  // Reconnect WiFi if dropped
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
  }

  unsigned long now = millis();
  if (now - lastPoll >= POLL_INTERVAL_MS) {
    lastPoll = now;

    String newStatus = fetchStatus();
    if (newStatus.length() == 0) {
      Serial.println("[Monitor] Failed to get status. Keeping previous state.");
      return;
    }

    currentStatus = newStatus;

    if (currentStatus == "CONFIRMED") {
      activateAlert();
    } else {
      deactivateAlert();
    }
  }
}

#include <Arduino.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <time.h> 

#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// --- Wi-Fi Credentials ---
#define WIFI_SSID "Nisal"
#define WIFI_PASSWORD "Nisaldilmina"

// --- Firebase Credentials ---
#define API_KEY "AIzaSyBovrj7QQugtrJt9KsAAxe_R8bWtHQpACo"
#define DATABASE_URL "neonet-6582d-default-rtdb.asia-southeast1.firebasedatabase.app"

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// --- Time Configuration (Sri Lanka UTC+5:30) ---
const char* ntpServer = "pool.ntp.org";
const long  gmtOffset_sec = 19800; // 5.5 hours * 3600
const int   daylightOffset_sec = 0;

// --- Hardware Pins (Water Quality & Flow Sensors) ---
const int TURBIDITY_PIN = 32;
const int TDS_PIN       = 34;

const int FLOW_MAIN_PIN = 27; // FS-01: Main Header Inlet
const int FLOW_A1_PIN   = 14; // FS-02: Branch A Inlet
const int FLOW_A2_PIN   = 25; // FS-03: Branch A Downstream
const int FLOW_B1_PIN   = 26; // FS-04: Branch B Inlet
const int FLOW_B2_PIN   = 33; // FS-05: Branch B Downstream

// --- Ultrasonic & Circulation Pump Pins ---
const int TRIG_PIN      = 5;  // Ultrasonic TRIG
const int ECHO_PIN      = 4;  // Ultrasonic ECHO
const int CIRC_PUMP_PIN = 23; // Circulation Pump Relay (Active-Low)

// --- Actuator Pins (Valves & Booster Pump) ---
const int VALVE1_PIN = 19; // VL-01: Branch A Cutoff (Active-Low)
const int VALVE2_PIN = 18; // VL-02: Branch B Cutoff (Active-Low)
const int PUMP_PIN   = 21; // PM-01: 12V Booster Pump (Active-High)

bool isValve1Open = false;
bool isValve2Open = false;
bool isAutoMode   = false;
bool isCircPumpOn = true; // Default ON

// --- Calibration & Threshold Variables ---
const float FLOW_CALIBRATION = 7.5; 
float TDS_CALIBRATION        = 2.0;        
const float LEAK_THRESHOLD   = 7.0;  // mL/s differential threshold for leak failover

// --- Water Level Variables ---
const float TANK_HEIGHT_CM = 28.0; 
float tankLevelPercent = 0.0;      
float currentDistanceCm = 10.0;    

// --- Volatile Pulse Counters ---
volatile unsigned long pulse_main = 0;
volatile unsigned long pulse_a1   = 0;
volatile unsigned long pulse_a2   = 0;
volatile unsigned long pulse_b1   = 0;
volatile unsigned long pulse_b2   = 0;

portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

unsigned long previousMillis = 0;
unsigned long previousHistoryMillis = 0;
unsigned long previousUltraMillis = 0; 

const unsigned long interval = 1000;         // 1 second live update
const unsigned long historyInterval = 60000; // 60 seconds (1 min) graph log

float flow_main_mL_s = 0.0, flow_a1_mL_s = 0.0, flow_a2_mL_s = 0.0, flow_b1_mL_s = 0.0, flow_b2_mL_s = 0.0;
float totalMilliLitres = 0.0;

void IRAM_ATTR countMain() { portENTER_CRITICAL_ISR(&mux); pulse_main++; portEXIT_CRITICAL_ISR(&mux); }
void IRAM_ATTR countA1()   { portENTER_CRITICAL_ISR(&mux); pulse_a1++;   portEXIT_CRITICAL_ISR(&mux); }
void IRAM_ATTR countA2()   { portENTER_CRITICAL_ISR(&mux); pulse_a2++;   portEXIT_CRITICAL_ISR(&mux); }
void IRAM_ATTR countB1()   { portENTER_CRITICAL_ISR(&mux); pulse_b1++;   portEXIT_CRITICAL_ISR(&mux); }
void IRAM_ATTR countB2()   { portENTER_CRITICAL_ISR(&mux); pulse_b2++;   portEXIT_CRITICAL_ISR(&mux); }

float calculateFlowMLs(unsigned long pulses, unsigned long elapsedTime) {
  float frequency = (pulses * 1000.0) / elapsedTime;
  float flowRate_L_min = frequency / FLOW_CALIBRATION;
  return (flowRate_L_min * 1000.0) / 60.0;
}

unsigned long getTime() {
  time_t now;
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) {
    return 0;
  }
  time(&now);
  return now;
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);

  // Initialize Relays Safely
  pinMode(VALVE1_PIN, OUTPUT);    digitalWrite(VALVE1_PIN, HIGH);    // Active-Low: HIGH = CLOSED
  pinMode(VALVE2_PIN, OUTPUT);    digitalWrite(VALVE2_PIN, HIGH);    // Active-Low: HIGH = CLOSED
  pinMode(PUMP_PIN, OUTPUT);      digitalWrite(PUMP_PIN, LOW);       // Active-High: LOW = OFF
  pinMode(CIRC_PUMP_PIN, OUTPUT); digitalWrite(CIRC_PUMP_PIN, LOW);  // Start ON (Active-Low: LOW = ON)

  // Initialize Ultrasonic Pins
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  // Initialize Flow & Quality Sensor Pins
  pinMode(FLOW_MAIN_PIN, INPUT_PULLUP); 
  pinMode(FLOW_A1_PIN, INPUT_PULLUP); 
  pinMode(FLOW_A2_PIN, INPUT_PULLUP);
  pinMode(FLOW_B1_PIN, INPUT_PULLUP); 
  pinMode(FLOW_B2_PIN, INPUT_PULLUP);
  pinMode(TURBIDITY_PIN, INPUT); 
  pinMode(TDS_PIN, INPUT);

  attachInterrupt(digitalPinToInterrupt(FLOW_MAIN_PIN), countMain, FALLING);
  attachInterrupt(digitalPinToInterrupt(FLOW_A1_PIN), countA1, FALLING);
  attachInterrupt(digitalPinToInterrupt(FLOW_A2_PIN), countA2, FALLING);
  attachInterrupt(digitalPinToInterrupt(FLOW_B1_PIN), countB1, FALLING);
  attachInterrupt(digitalPinToInterrupt(FLOW_B2_PIN), countB2, FALLING);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(300);
  }
  Serial.println("\nConnected to Wi-Fi!");

  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
  Serial.println("Waiting for NTP time sync...");
  while (getTime() < 100000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nTime synchronized.");

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  config.signer.test_mode = true;
  
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  Firebase.RTDB.setString(&fbdo, "valves/valve1", "CLOSED");
  Firebase.RTDB.setString(&fbdo, "valves/valve2", "CLOSED");
  Firebase.RTDB.setString(&fbdo, "valves/pump", "OFF");
  Firebase.RTDB.setString(&fbdo, "valves/auto_mode", "OFF");
  Firebase.RTDB.setString(&fbdo, "valves/circ_pump", "ON");

  previousMillis = millis();
  previousHistoryMillis = millis();
  previousUltraMillis = millis();
}

void loop() {
  unsigned long currentMillis = millis();

  // --- EXACT WORKING PUMP + ULTRASONIC LOOP (UNTOUCHED) ---
  if (currentMillis - previousUltraMillis >= 200) {
    previousUltraMillis = currentMillis;

    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);

    long duration = pulseIn(ECHO_PIN, HIGH, 25000); 

    if (duration > 0) {
      currentDistanceCm = (duration * 0.0343) / 2.0;

      // Pump mechanism left 100% untouched as requested
      if (currentDistanceCm < 5.0) {
        digitalWrite(CIRC_PUMP_PIN, HIGH); // Active-Low HIGH = OFF
        isCircPumpOn = false;
      } else {
        digitalWrite(CIRC_PUMP_PIN, LOW);  // Active-Low LOW = ON
        isCircPumpOn = true;
      }

      // Parallel calculation for app water level percentage (0% to 100%)
      float waterDepth = TANK_HEIGHT_CM - currentDistanceCm;
      tankLevelPercent = (waterDepth / TANK_HEIGHT_CM) * 100.0;
      if (tankLevelPercent > 100.0) tankLevelPercent = 100.0;
      if (tankLevelPercent < 0.0) tankLevelPercent = 0.0;
    }
  }

  // --- 1-SECOND SENSOR & FIREBASE SYNC LOOP ---
  if (currentMillis - previousMillis >= interval) {
    unsigned long pm = 0, pa1 = 0, pa2 = 0, pb1 = 0, pb2 = 0;
    
    portENTER_CRITICAL(&mux);
    pm = pulse_main; pulse_main = 0; 
    pa1 = pulse_a1;  pulse_a1 = 0; 
    pa2 = pulse_a2;  pulse_a2 = 0; 
    pb1 = pulse_b1;  pulse_b1 = 0; 
    pb2 = pulse_b2;  pulse_b2 = 0;
    portEXIT_CRITICAL(&mux);

    unsigned long elapsedTime = currentMillis - previousMillis;
    previousMillis = currentMillis;

    flow_main_mL_s = calculateFlowMLs(pm, elapsedTime); 
    flow_a1_mL_s   = calculateFlowMLs(pa1, elapsedTime);
    flow_a2_mL_s   = calculateFlowMLs(pa2, elapsedTime); 
    flow_b1_mL_s   = calculateFlowMLs(pb1, elapsedTime);
    flow_b2_mL_s   = calculateFlowMLs(pb2, elapsedTime);
    
    float activeMainFlow = (flow_main_mL_s > 0.0) ? flow_main_mL_s : (flow_a1_mL_s + flow_b1_mL_s);
    totalMilliLitres += (activeMainFlow * (elapsedTime / 1000.0));

    // Turbidity Calculation
    long turbSum = 0;
    for (int i = 0; i < 20; i++) { turbSum += analogRead(TURBIDITY_PIN); delay(5); }
    int turbidityADC = turbSum / 20;
    String turbidityStatus = (turbidityADC >= 1600) ? "CLEAR WATER" : ((turbidityADC >= 1400) ? "SLIGHTLY TURBID" : "HIGHLY TURBID");

    // TDS Calculation
    long tdsSum = 0;
    for (int i = 0; i < 20; i++) { tdsSum += analogRead(TDS_PIN); delay(5); }
    int tdsADC = tdsSum / 20;
    float voltage = (tdsADC / 4095.0) * 3.3;
    float tdsPPM = ((133.42 * pow(voltage, 3) - 255.86 * pow(voltage, 2) + 857.39 * voltage) * 0.5) * TDS_CALIBRATION; 
    if (tdsPPM < 0) tdsPPM = 0;

    Serial.printf("Lvl: %.1f%% | Dist: %.1fcm | CircPump: %s | Flow: %.1ff\n", tankLevelPercent, currentDistanceCm, isCircPumpOn ? "ON" : "OFF", activeMainFlow);

    unsigned long timestamp = getTime();

    if (Firebase.ready()) {
      FirebaseJson json;
      json.set("timestamp", timestamp);
      json.set("turbidity_adc", turbidityADC);
      json.set("turbidity_status", turbidityStatus);
      json.set("tds_adc", tdsADC);
      json.set("tds_ppm", (int)tdsPPM);
      json.set("flow_main", activeMainFlow);
      json.set("flow_a1", flow_a1_mL_s); 
      json.set("flow_a2", flow_a2_mL_s); 
      json.set("flow_b1", flow_b1_mL_s); 
      json.set("flow_b2", flow_b2_mL_s); 
      json.set("total_l", totalMilliLitres / 1000.0);
      
      // Send the clamped water level percentage to Firebase for your app
      json.set("tank_percent", tankLevelPercent); 
      
      Firebase.RTDB.setJSON(&fbdo, "sensors/current", &json);
      Firebase.RTDB.setString(&fbdo, "valves/circ_pump", isCircPumpOn ? "ON" : "OFF");

      if (Firebase.RTDB.getString(&fbdo, "valves/auto_mode")) {
        isAutoMode = (fbdo.stringData() == "ON");
      }
      if (Firebase.RTDB.getString(&fbdo, "valves/valve1")) {
        isValve1Open = (fbdo.stringData() == "OPEN");
      }
      if (Firebase.RTDB.getString(&fbdo, "valves/valve2")) {
        isValve2Open = (fbdo.stringData() == "OPEN");
      }

      if (isAutoMode) {
        bool leakInA = (flow_a1_mL_s > 0.0) && ((flow_a1_mL_s - flow_a2_mL_s) > LEAK_THRESHOLD);
        bool leakInB = (flow_b1_mL_s > 0.0) && ((flow_b1_mL_s - flow_b2_mL_s) > LEAK_THRESHOLD);

        if (leakInA && isValve1Open) {
          isValve1Open = false;
          isValve2Open = true;
          Firebase.RTDB.setString(&fbdo, "valves/valve1", "CLOSED");
          Firebase.RTDB.setString(&fbdo, "valves/valve2", "OPEN");
        } 
        else if (leakInB && isValve2Open) {
          isValve2Open = false;
          isValve1Open = true;
          Firebase.RTDB.setString(&fbdo, "valves/valve2", "CLOSED");
          Firebase.RTDB.setString(&fbdo, "valves/valve1", "OPEN");
        }
      }

      digitalWrite(VALVE1_PIN, isValve1Open ? LOW : HIGH);
      digitalWrite(VALVE2_PIN, isValve2Open ? LOW : HIGH);

      bool isPumpNeeded = (isValve1Open || isValve2Open);
      digitalWrite(PUMP_PIN, isPumpNeeded ? HIGH : LOW);
      Firebase.RTDB.setString(&fbdo, "valves/pump", isPumpNeeded ? "ON" : "OFF");
    }
  }

  // --- 1-MINUTE HISTORY LOG LOOP ---
  if (currentMillis - previousHistoryMillis >= historyInterval) {
    previousHistoryMillis = currentMillis;
    if (Firebase.ready()) {
      float activeMainFlow = (flow_main_mL_s > 0.0) ? flow_main_mL_s : (flow_a1_mL_s + flow_b1_mL_s);
      FirebaseJson historyJson;
      historyJson.set("timestamp", getTime());
      historyJson.set("total_l", totalMilliLitres / 1000.0);
      historyJson.set("flow_main", activeMainFlow);
      Firebase.RTDB.pushJSON(&fbdo, "sensors/history", &historyJson);
    }
  }
}
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>

const char* AP_SSID = "NeoNet_ESP32";
const char* AP_PASS = "12345678";
WebServer server(80);

const int TURBIDITY_PIN = 32;
const int TDS_PIN = 34;

const int FLOW_MAIN_PIN = 27; 
const int FLOW_A1_PIN   = 14; 
const int FLOW_A2_PIN   = 25; 
const int FLOW_B1_PIN   = 26; 
const int FLOW_B2_PIN   = 33; 

const int VALVE1_PIN = 19; 
const int VALVE2_PIN = 18; 
bool isValve1Open = false;
bool isValve2Open = false;

const float FLOW_CALIBRATION = 7.5; 
float TDS_CALIBRATION = 2.0;        

volatile unsigned long pulse_main = 0;
volatile unsigned long pulse_a1 = 0;
volatile unsigned long pulse_a2 = 0;
volatile unsigned long pulse_b1 = 0;
volatile unsigned long pulse_b2 = 0;

portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

unsigned long previousMillis = 0;
const unsigned long interval = 1000;

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

void handleValveControl() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  if (server.hasArg("id") && server.hasArg("state")) {
    int valveId = server.arg("id").toInt();
    String state = server.arg("state");
    bool turnOn = (state == "open");

    if (valveId == 1) {
      digitalWrite(VALVE1_PIN, turnOn ? HIGH : LOW);
      isValve1Open = turnOn;
    } else if (valveId == 2) {
      digitalWrite(VALVE2_PIN, turnOn ? HIGH : LOW);
      isValve2Open = turnOn;
    }
  }
  server.send(200, "text/plain", "OK");
}

void handleData() {
  long turbSum = 0;
  for (int i = 0; i < 20; i++) { turbSum += analogRead(TURBIDITY_PIN); delay(5); }
  int turbidityADC = turbSum / 20;
  String turbidityStatus = (turbidityADC >= 1600) ? "CLEAR WATER" : ((turbidityADC >= 1400) ? "SLIGHTLY TURBID" : "HIGHLY TURBID");

  long tdsSum = 0;
  for (int i = 0; i < 20; i++) { tdsSum += analogRead(TDS_PIN); delay(5); }
  int tdsADC = tdsSum / 20;
  float voltage = (tdsADC / 4095.0) * 3.3;
  float tdsPPM = ((133.42 * pow(voltage, 3) - 255.86 * pow(voltage, 2) + 857.39 * voltage) * 0.5) * TDS_CALIBRATION; 
  if (tdsPPM < 0) tdsPPM = 0;
  String tdsStatus = (tdsPPM <= 300) ? "EXCELLENT" : ((tdsPPM <= 600) ? "GOOD" : ((tdsPPM <= 900) ? "FAIR" : "POOR"));

  String json = "{";
  json += "\"turbidity_adc\":" + String(turbidityADC) + ",\"turbidity_status\":\"" + turbidityStatus + "\",";
  json += "\"tds_adc\":" + String(tdsADC) + ",\"tds_ppm\":" + String((int)tdsPPM) + ",\"tds_status\":\"" + tdsStatus + "\",";
  json += "\"flow_main\":" + String(flow_main_mL_s, 2) + ",\"total_l\":" + String(totalMilliLitres / 1000.0, 3) + ",";
  json += "\"flow_a1\":" + String(flow_a1_mL_s, 2) + ",\"flow_a2\":" + String(flow_a2_mL_s, 2) + ",";
  json += "\"flow_b1\":" + String(flow_b1_mL_s, 2) + ",\"flow_b2\":" + String(flow_b2_mL_s, 2) + ",";
  json += "\"valve1_status\":\"" + String(isValve1Open ? "OPEN" : "CLOSED") + "\",";
  json += "\"valve2_status\":\"" + String(isValve2Open ? "OPEN" : "CLOSED") + "\"";
  json += "}";

  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(200, "application/json", json);
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);

  pinMode(VALVE1_PIN, OUTPUT); digitalWrite(VALVE1_PIN, LOW);
  pinMode(VALVE2_PIN, OUTPUT); digitalWrite(VALVE2_PIN, LOW);

  pinMode(FLOW_MAIN_PIN, INPUT_PULLUP); pinMode(FLOW_A1_PIN, INPUT_PULLUP); pinMode(FLOW_A2_PIN, INPUT_PULLUP);
  pinMode(FLOW_B1_PIN, INPUT_PULLUP); pinMode(FLOW_B2_PIN, INPUT_PULLUP);
  pinMode(TURBIDITY_PIN, INPUT); pinMode(TDS_PIN, INPUT);

  attachInterrupt(digitalPinToInterrupt(FLOW_MAIN_PIN), countMain, FALLING);
  attachInterrupt(digitalPinToInterrupt(FLOW_A1_PIN), countA1, FALLING);
  attachInterrupt(digitalPinToInterrupt(FLOW_A2_PIN), countA2, FALLING);
  attachInterrupt(digitalPinToInterrupt(FLOW_B1_PIN), countB1, FALLING);
  attachInterrupt(digitalPinToInterrupt(FLOW_B2_PIN), countB2, FALLING);

  previousMillis = millis();
  
  WiFi.softAP(AP_SSID, AP_PASS);
  
  server.on("/data", HTTP_GET, handleData);
  server.on("/valve", HTTP_GET, handleValveControl); 
  
  server.begin();
}

void loop() {
  server.handleClient();
  
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= interval) {
    unsigned long pm = 0, pa1 = 0, pa2 = 0, pb1 = 0, pb2 = 0;
    
    portENTER_CRITICAL(&mux);
    pm = pulse_main; pulse_main = 0; 
    pa1 = pulse_a1; pulse_a1 = 0; 
    pa2 = pulse_a2; pulse_a2 = 0; 
    pb1 = pulse_b1; pulse_b1 = 0; 
    pb2 = pulse_b2; pulse_b2 = 0;
    portEXIT_CRITICAL(&mux);

    unsigned long elapsedTime = currentMillis - previousMillis;
    previousMillis = currentMillis;

    flow_main_mL_s = calculateFlowMLs(pm, elapsedTime); 
    flow_a1_mL_s = calculateFlowMLs(pa1, elapsedTime);
    flow_a2_mL_s = calculateFlowMLs(pa2, elapsedTime); 
    flow_b1_mL_s = calculateFlowMLs(pb1, elapsedTime);
    flow_b2_mL_s = calculateFlowMLs(pb2, elapsedTime);
    
    totalMilliLitres += (flow_main_mL_s * (elapsedTime / 1000.0));
  }
}
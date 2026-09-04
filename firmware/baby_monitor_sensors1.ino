#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <time.h>

// ── Capteurs ──────────────────────────────────────────────
#include "MAX30105.h"          // SparkFun MAX3010x library
#include "spo2_algorithm.h"    // SparkFun MAX3010x library
#include "heartRate.h"         // SparkFun MAX3010x library
#include <DHT.h>               // DHT sensor library (Adafruit)

// ── Broches ───────────────────────────────────────────────
#define DHT_PIN        14       // DHT22 DATA
#define DHT_TYPE       DHT22
#define SOUND_PIN      34      // Micro analogique (ADC)
#define ECG_PIN        35      // AD8232 OUTPUT (ADC)
#define ECG_LO_PLUS    32      // AD8232 LO+ (détection électrode)
#define ECG_LO_MINUS   33      // AD8232 LO- (détection électrode)

// ── WiFi / MQTT ───────────────────────────────────────────
const char* WIFI_SSID     = "ton-wifi";
const char* WIFI_PASSWORD = "ton_pwd_wifi";
const char* MQTT_SERVER   = "ip-server";
const int   MQTT_PORT     = 8883;
const char* MQTT_USER     = "mqtt-user";
const char* MQTT_PASS     = "mqtt-pwd";
const char* LIT_ID        = "lit6";

const char* CA_CERT = R"EOF(
-----BEGIN CERTIFICATE-----
[certificat]
-----END CERTIFICATE-----
)EOF";

// ── Objets capteurs ───────────────────────────────────────
MAX30105 particleSensor;
DHT dht(DHT_PIN, DHT_TYPE);

WiFiClientSecure espClient;
PubSubClient mqtt(espClient);

// ── Buffers MAX30102 (SpO2) ───────────────────────────────
#define BUFFER_SIZE 100
uint32_t irBuffer[BUFFER_SIZE];
uint32_t redBuffer[BUFFER_SIZE];
int32_t  spo2Value      = 0;
int8_t   spo2Valid      = 0;
int32_t  heartRateValue = 0;
int8_t   hrValid        = 0;

// ── Seuil détection pleurs (micro) ───────────────────────
// Ajuste cette valeur selon ton micro (0–4095)
// En dessous → silence, au-dessus → pleurs détectés
#define CRYING_THRESHOLD  1800

// ── Timing ────────────────────────────────────────────────
unsigned long lastPublish    = 0;
unsigned long lastSpo2Update = 0;
const unsigned long PUBLISH_INTERVAL   = 2000;   // ms
const unsigned long SPO2_UPDATE_INTERVAL = 4000; // ms (100 échantillons × ~25ms)

// ─────────────────────────────────────────────────────────
void connectWiFi() {
  Serial.print("Connexion WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n WiFi connecté");
  Serial.print(" IP: ");
  Serial.println(WiFi.localIP());
}

void syncTime() {
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Synchronisation NTP");
  time_t now = time(nullptr);
  while (now < 1000000000) {
    delay(500);
    Serial.print(".");
    now = time(nullptr);
  }
  Serial.println(" ✅");
}

void reconnectMQTT() {
  while (!mqtt.connected()) {
    Serial.print("Connexion MQTT-TLS...");
    String clientId = "ESP32-" + String(LIT_ID);
    if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)) {
      Serial.println(" MQTT-TLS connecté");
    } else {
      int rc = mqtt.state();
      Serial.print("Échec rc=");
      Serial.print(rc);
      switch (rc) {
        case -2: Serial.print(" (RESEAU)");       break;
        case -1: Serial.print(" (DISCONNECT)");   break;
        case  1: Serial.print(" (PROTOCOLE)");    break;
        case  2: Serial.print(" (CLIENT ID)");    break;
        case  3: Serial.print(" (SERVEUR)");      break;
        case  4: Serial.print(" (USER/PASS)");    break;
        case  5: Serial.print(" (NON AUTORISE)"); break;
      }
      Serial.println(" → retry 2s");
      delay(2000);
    }
  }
}

// ── Lecture MAX30102 : SpO2 + FC + température ────────────
void updateMAX30102() {
  // Remplissage du buffer (100 échantillons)
  for (int i = 0; i < BUFFER_SIZE; i++) {
    while (!particleSensor.available()) particleSensor.check();
    redBuffer[i] = particleSensor.getRed();
    irBuffer[i]  = particleSensor.getIR();
    particleSensor.nextSample();
  }
  // Calcul SpO2 et FC via l'algorithme SparkFun
  maxim_heart_rate_and_oxygen_saturation(
    irBuffer, BUFFER_SIZE, redBuffer,
    &spo2Value, &spo2Valid,
    &heartRateValue, &hrValid
  );
}

// ── Lecture ECG brut (AD8232) ─────────────────────────────
int readECG() {
  // Si une électrode est déconnectée → retourne -1
  if (digitalRead(ECG_LO_PLUS) == HIGH || digitalRead(ECG_LO_MINUS) == HIGH) {
    return -1;
  }
  return analogRead(ECG_PIN);   // 0–4095 (12 bits ESP32)
}

// ── Lecture niveau sonore moyen ───────────────────────────
int readSoundLevel() {
  long sum = 0;
  const int samples = 32;
  for (int i = 0; i < samples; i++) {
    sum += analogRead(SOUND_PIN);
    delayMicroseconds(200);
  }
  return (int)(sum / samples);  // valeur brute 0–4095
}

// ── Publication MQTT ──────────────────────────────────────
void publishData() {
  // --- MAX30102 ---
  float tempBody = particleSensor.readTemperature();  // °C

  // --- DHT22 ---
  float tempEnv = dht.readTemperature();
  float hum     = dht.readHumidity();
  if (isnan(tempEnv)) tempEnv = -1;
  if (isnan(hum))     hum     = -1;

  // --- AD8232 ---
  int ecgRaw = readECG();

  // --- Microphone → détection pleurs ---
  int soundRaw = readSoundLevel();
  bool crying  = (soundRaw > CRYING_THRESHOLD);

  // ── JSON — noms de champs exacts attendus par index.js ──
  // backend lit : bpm, spo2, temp_body, humidite, crying
  StaticJsonDocument<300> doc;
  doc["bpm"]       = (hrValid)   ? heartRateValue : 0;   // ← "hr" renommé "bpm"
  doc["spo2"]      = (spo2Valid) ? spo2Value      : 0;
  doc["temp_body"] = tempBody;
  doc["humidite"]  = (hum >= 0)  ? hum : 0;              // ← "hum" renommé "humidite"
  doc["crying"]    = crying;                              // ← booléen (remplace "sound")
  // Champs supplémentaires (non utilisés par InfluxDB mais utiles pour debug)
  doc["temp_env"]  = tempEnv;
  doc["ecg"]       = ecgRaw;
  doc["sound_raw"] = soundRaw;

  char payload[300];
  serializeJson(doc, payload);
  String topic = "baby/sensors/" + String(LIT_ID);

  bool published = mqtt.publish(topic.c_str(), payload);

  Serial.println("============================");
  Serial.print("📤 Topic   : "); Serial.println(topic);
  Serial.print("📦 Payload : "); Serial.println(payload);
  Serial.print("💓 bpm     : "); Serial.print(heartRateValue); Serial.println(hrValid  ? " bpm ✅" : " bpm ⚠️ invalide");
  Serial.print("🩸 spo2    : "); Serial.print(spo2Value);      Serial.println(spo2Valid ? " % ✅"  : " % ⚠️ invalide");
  Serial.print("🌡️ temp_body: "); Serial.print(tempBody);      Serial.println(" °C");
  Serial.print("🌡️ temp_env : "); Serial.print(tempEnv);       Serial.println(" °C");
  Serial.print("💧 humidite: "); Serial.print(hum);            Serial.println(" %");
  Serial.print("❤️ ECG     : "); Serial.println(ecgRaw == -1 ? "électrode déco" : String(ecgRaw));
  Serial.print("🔊 sound   : "); Serial.print(soundRaw);       Serial.print("  →  crying: "); Serial.println(crying ? "true 😭" : "false 😴");
  Serial.print("🔐 TLS     : "); Serial.println(published ? "Publié OK ✅" : "ÉCHEC ❌");
  Serial.println("============================");
}

// ─────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(1000);

  // AD8232 – broches détection électrodes
  pinMode(ECG_LO_PLUS,  INPUT);
  pinMode(ECG_LO_MINUS, INPUT);

  // DHT22
  dht.begin();

  // MAX30102 (I2C par défaut : SDA=21, SCL=22)
  if (!particleSensor.begin()) {
    Serial.println("MAX30102 non détecté ! Vérifiez le câblage I2C.");
    while (true) delay(1000);
  }
  particleSensor.setup();                        // config par défaut
  particleSensor.setPulseAmplitudeRed(0x0A);     // LED rouge faible
  particleSensor.setPulseAmplitudeGreen(0);      // LED verte OFF
  particleSensor.enableDIETEMPRDY();             // active capteur temp interne

  connectWiFi();
  syncTime();

  Serial.println("MODE TEST : setInsecure() activé");
  espClient.setInsecure();
  // Pour la production, remplacer par : espClient.setCACert(CA_CERT);

  mqtt.setServer(MQTT_SERVER, MQTT_PORT);

  // Première acquisition SpO2/FC avant la loop
  Serial.println("Acquisition initiale MAX30102...");
  updateMAX30102();
  lastSpo2Update = millis();
}

void loop() {
  if (!mqtt.connected()) reconnectMQTT();
  mqtt.loop();

  // Mise à jour SpO2/FC toutes les ~4 secondes (100 échantillons)
  if (millis() - lastSpo2Update > SPO2_UPDATE_INTERVAL) {
    updateMAX30102();
    lastSpo2Update = millis();
  }

  // Publication MQTT toutes les 2 secondes
  if (millis() - lastPublish > PUBLISH_INTERVAL) {
    lastPublish = millis();
    publishData();
  }
}

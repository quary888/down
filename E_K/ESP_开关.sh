#定义变量
Q_URL=http://192.168.50.2:88
Q_sleep=10 #延时 秒
##################
Q_ID=设备识别码 (如 ESP.getChipId())
Q_URL=Q_URL+"/"+$设备识别码

检查是否已经保存WIFI信息 如果没有就进入 配置模式 如果已经保存有就进入 正常运行

配置模式{ 
开启一个热点(AP模式) SSID=ESP_$Q_ID(意思是"ESP_"+Q_ID) 无密码 ,同时建立httpserver 监听80端口
用户访问 :80 返回一个简单的WEB_UI
输入框_WIFI_SSID,输入框_WIFI_PASS,按钮_提交]
得到WIFI信息后 wifi连接网络
连接成功就保存信息 进入 正常运行 连接失败 再次进入 配置模式
}

复位(短接(RST+GND)){
恢复默认信息 也就是删掉wifi信息 进入 配置模式
}

正常运行{

如果  访问 $Q_URL
    状态码≠200:检查是否连接网络 如果没有则读取WIFI信息连接WIFI
    状态码=200:{
            (body为一个字节)
            如果 body=0 继电器 状态 不等于 断开 则断开
            如果 body=1 继电器 状态 不等于 闭合 则闭合
            }
延时 $Q_sleep 秒 无限循环
}
IDE 用 Arduino

捷兴泰电子
https://item.taobao.com/item.htm?abbucket=6&id=738459519151&mi_id=0000_P_7rkNFThdD_9v7_Uwv5tn741BM7DQpASfipzu3Xhc&ns=1&skuId=5265126638042&spm=a21n57.1.hoverItem.2&xxc=taobaoSearch







#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <EEPROM.h>
#include <ESP8266HTTPClient.h>

#define RELAY_PIN 0       // GPIO0 控制继电器
#define EEPROM_SIZE 96
#define Q_sleep 10        // 延时 秒
String Q_URL = "http://192.168.50.2:88";  // 基础 URL

ESP8266WebServer server(80);

char wifiSSID[32];
char wifiPASS[64];
bool wifiConfigured = false;
uint32_t Q_ID;

// ------------- EEPROM ----------------
void loadWiFiInfo() {
  EEPROM.begin(EEPROM_SIZE);
  for (int i = 0; i < 32; i++) wifiSSID[i] = EEPROM.read(i);
  for (int i = 0; i < 64; i++) wifiPASS[i] = EEPROM.read(i + 32);
  if (strlen(wifiSSID) > 0) wifiConfigured = true;
}

void saveWiFiInfo(const char* ssid, const char* pass) {
  for (int i = 0; i < 32; i++) EEPROM.write(i, 0);
  for (int i = 0; i < 64; i++) EEPROM.write(i + 32, 0);
  strncpy(wifiSSID, ssid, 32);
  strncpy(wifiPASS, pass, 64);
  for (int i = 0; i < 32; i++) EEPROM.write(i, wifiSSID[i]);
  for (int i = 0; i < 64; i++) EEPROM.write(i + 32, wifiPASS[i]);
  EEPROM.commit();
  wifiConfigured = true;
}

void clearWiFiInfo() {
  for (int i = 0; i < EEPROM_SIZE; i++) EEPROM.write(i, 0);
  EEPROM.commit();
  wifiConfigured = false;
}

// ------------- 配置模式 ----------------
void handleRoot() {
  if (server.hasArg("ssid") && server.hasArg("pass")) {
    String ssid = server.arg("ssid");
    String pass = server.arg("pass");
    saveWiFiInfo(ssid.c_str(), pass.c_str());
    server.send(200, "text/plain", "WiFi info saved. Rebooting...");
    delay(1000);
    ESP.restart();
  } else {
    String page = "<h1>Configure WiFi</h1>";
    page += "<p>Device ID: " + String(Q_ID) + "</p>";
    page += "<form method='get'>";
    page += "SSID: <input name='ssid'><br>";
    page += "PASS: <input name='pass'><br>";
    page += "<input type='submit' value='Save'>";
    page += "</form>";
    server.send(200, "text/html", page);
  }
}

// ------------- Wi-Fi 连接 ----------------
bool connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSSID, wifiPASS);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(500);
  }
  return WiFi.status() == WL_CONNECTED;
}

// ------------- 正常运行 ----------------
void updateRelay() {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  http.begin(Q_URL);
  int code = http.GET();
  if (code == 200) {
    String payload = http.getString();
    payload.trim();
    if (payload == "1" && digitalRead(RELAY_PIN) == LOW) digitalWrite(RELAY_PIN, HIGH);
    if (payload == "0" && digitalRead(RELAY_PIN) == HIGH) digitalWrite(RELAY_PIN, LOW);
  } else {
    // 网络异常，尝试重新连接 Wi-Fi
    connectWiFi();
  }
  http.end();
}

// ------------- setup ----------------
void setup() {
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);
  Serial.begin(115200);

  Q_ID = ESP.getChipId();
  Q_URL += "/" + String(Q_ID);

  loadWiFiInfo();

  if (!wifiConfigured || !connectWiFi()) {
    // 配置模式
    WiFi.mode(WIFI_AP);
    String apName = "ESP_" + String(Q_ID);
    WiFi.softAP(apName.c_str());
    server.on("/", handleRoot);
    server.begin();
    Serial.println("AP Mode started. Connect to " + apName + " to configure WiFi.");
  } else {
    Serial.println("WiFi connected: " + String(WiFi.SSID()));
  }
}

// ------------- loop ----------------
void loop() {
  if (!wifiConfigured || WiFi.status() != WL_CONNECTED) {
    server.handleClient(); // 配置模式
    return;
  }

  // 正常运行模式
  updateRelay();
  delay(Q_sleep * 1000);
}

#include <BluetoothSerial.h>
#include <Arduino.h>

BluetoothSerial SerialBT;

const int indicatorLedPin = 25; // GPIO pin for the indicator LED (adjust as necessary)
const int pwmPin = 18; // GPIO pin connected to the MOSFET gate

unsigned long startTime; // For tracking elapsed time
int maxIntensity = 0; // Maximum light intensity (0-100%), received from app
int LED_pwm_norm_value = 0; // Current LED PWM value (0-100)
float on_cycle_hours = 0; // ON cycle in hours (received from app)
float off_cycle_hours = 24; // OFF cycle in hours (received from app)
float dataIntervalMinutes = 1.0; // Data interval in minutes, adjustable via Bluetooth or Serial
bool transitionEnabled = true; // Transition feature state (enabled by default)

unsigned long previousPWMUpdateMillis = 0;
unsigned long previousMillis = 0; // For tracking data send/receive intervals
unsigned long lastReadMillis = 0; // For tracking non-blocking delay for both Bluetooth and Serial
unsigned long lastBlinkMillis = 0; // For non-blocking LED blinking
bool isLedOn = false; // Track LED state for blinking
bool initialDataSent = false; // Flag to ensure initial data is sent
bool dataUpdated = false; // Flag to track if data was updated through Bluetooth or USB

const int transitionTimeMinutes = 10; // Transition time in minutes for ramping intensity

// Variables for double blinking
bool isBlinking = false;        // Indicates if a blink sequence is active
int blinkCount = 0;             // Number of completed blinks
const int totalBlinks = 2;      // Total number of blinks desired
const int blinkDuration = 100; // Duration for LED on/off states in milliseconds

void setup() {
  Serial.begin(115200);
  SerialBT.begin("AlgaApp_BT"); // Bluetooth device name
  Serial.println("Bluetooth started. Waiting for connections...");
  
  // Define an array to hold the MAC address
  uint8_t mac[6];
  SerialBT.getBtAddress(mac);

  // Format the MAC address as a string
  String macStr = "";
  for (int i = 0; i < 6; i++) {
    macStr += String(mac[i], HEX);
    if (i < 5) {
      macStr += ":";
    }
  }

  // Convert to uppercase for better readability
  macStr.toUpperCase();

  // Print the MAC address
  Serial.println("ESP32 MAC Address: " + macStr);

  // Set up indicator LED
  pinMode(indicatorLedPin, OUTPUT);
  digitalWrite(indicatorLedPin, LOW); // Ensure the LED is off initially

  // Set up PWM pin
  pinMode(pwmPin, OUTPUT); // Set PWM pin as output

  startTime = millis(); // Initialize start time
}

void loop() {
  // Calculate the interval in milliseconds
  unsigned long intervalMillis = dataIntervalMinutes * 60000.0;
  unsigned long currentMillis = millis();

  // Ensure data is sent initially
  if (!initialDataSent) {
    sendData();
    initialDataSent = true;
  }

  // Send and read data periodically based on the set interval
  if (currentMillis - previousMillis >= intervalMillis) {
    previousMillis = currentMillis;
    sendData(); // Sends data over both Bluetooth and Serial
  }

  if (currentMillis - previousPWMUpdateMillis >= 1000) { // 1000 milliseconds = 1 second
    previousPWMUpdateMillis = currentMillis;
    controlLEDIntensity();
  }

  // Read incoming data with a non-blocking delay for both Bluetooth and Serial
  if (currentMillis - lastReadMillis >= 150) { // 150 ms delay
    lastReadMillis = currentMillis;
    dataUpdated |= readData(); // Reads data from both Bluetooth and Serial
  }

  // Send data immediately if there was an update
  if (dataUpdated) {
    sendData();
    dataUpdated = false; // Reset the update flag after sending data
  }

  // Handle non-blocking LED blinking
  handleIndicatorLedBlink();
}

void sendData() {
  float elapsed_time = (millis() - startTime) / 60000.0; // Elapsed time in minutes
  String jsonString = String("{\"time\":") + String(elapsed_time, 2) +
                      ",\"intensity\":" + String(maxIntensity) +
                      ",\"on\":" + String(on_cycle_hours, 1) +
                      ",\"off\":" + String(off_cycle_hours, 1) +
                      ",\"interval\":" + String(dataIntervalMinutes, 1) +
                      ",\"transition\":" + String(transitionEnabled ? 1 : 0) + "}";
  
  // Send data over Bluetooth
  SerialBT.println(jsonString);
  // Send data over Serial USB
  Serial.println("Sent: " + jsonString);
}

bool readData() {
  bool updated = false; // Track if any data is updated

  // Read from Bluetooth
  if (SerialBT.available()) {
    String data = SerialBT.readStringUntil('\n');
    data.trim();
    updated |= processReceivedData(data);
  }

  // Read from Serial USB
  if (Serial.available()) {
    String data = Serial.readStringUntil('\n');
    data.trim();
    updated |= processReceivedData(data);
  }

  // Initiate double blink if data was updated
  if (updated) {
    initiateDoubleBlink();
  }

  return updated;
}

bool processReceivedData(String data) {
  bool updated = false; // Track if any data is updated

  if (data[0] == '{' && data[data.length() - 1] == '}') {
    data = data.substring(1, data.length() - 1); // Remove braces
    int start = 0;
    while (start < data.length()) {
      int colonIndex = data.indexOf(':', start);
      int commaIndex = data.indexOf(',', start);

      if (commaIndex == -1) {
        commaIndex = data.length(); // Last element
      }

      if (colonIndex != -1 && colonIndex < commaIndex) {
        String key = data.substring(start, colonIndex);
        String value = data.substring(colonIndex + 1, commaIndex);
        key.trim();
        value.trim();

        // Update variables based on received key-value pairs and set updated flag
        if (key == "\"intensity\"") {
          maxIntensity = value.toInt();
          updated = true;
          Serial.println("Updated max intensity: " + String(maxIntensity));
        } else if (key == "\"on\"") {
          on_cycle_hours = value.toFloat();
          updated = true;
          Serial.println("Updated on cycle (hours): " + String(on_cycle_hours));
        } else if (key == "\"off\"") {
          off_cycle_hours = value.toFloat();
          updated = true;
          Serial.println("Updated off cycle (hours): " + String(off_cycle_hours));
        } else if (key == "\"interval\"") {
          dataIntervalMinutes = value.toFloat();
          updated = true;
          Serial.println("Updated data interval (minutes): " + String(dataIntervalMinutes));
        } else if (key == "\"transition\"") {
          transitionEnabled = (value.toInt() == 1);
          updated = true;
          Serial.println("Updated transition state: " + String(transitionEnabled ? "Enabled" : "Disabled"));
        }
      }
      start = commaIndex + 1;
    }
  } else {
    Serial.println("Invalid data format received: " + data);
  }

  return updated;
}

void controlLEDIntensity() {
  unsigned long elapsedMinutes = (millis() - startTime) / 60000; // Elapsed time in minutes
  int on_cycle_minutes = on_cycle_hours * 60; // Convert ON cycle to minutes
  int off_cycle_minutes = off_cycle_hours * 60; // Convert OFF cycle to minutes
  int cycleDuration = on_cycle_minutes + off_cycle_minutes;
  int cyclePosition = elapsedMinutes % cycleDuration;

  if (cyclePosition < on_cycle_minutes) {
    // During ON cycle with optional transition
    if (transitionEnabled && cyclePosition < transitionTimeMinutes) {
      // Transition from OFF to ON (0% to maxIntensity over transition time)
      LED_pwm_norm_value = (maxIntensity * cyclePosition) / transitionTimeMinutes;
    } else {
      // Steady ON at max intensity
      LED_pwm_norm_value = maxIntensity;
    }
  } else {
    // During OFF cycle with optional transition
    int offCyclePosition = cyclePosition - on_cycle_minutes;
    if (transitionEnabled && offCyclePosition < transitionTimeMinutes) {
      // Transition from ON to OFF (maxIntensity to 0% over transition time)
      LED_pwm_norm_value = maxIntensity - ((maxIntensity * offCyclePosition) / transitionTimeMinutes);
    } else {
      // Steady OFF at 0 intensity
      LED_pwm_norm_value = 0;
    }
  }

  // Map the 0-100% intensity value to a 0-255 PWM range for the LED strip
  int pwmValue = map(LED_pwm_norm_value, 0, 100, 0, 255);
  analogWrite(pwmPin, pwmValue); // Write the PWM value to the pin
  Serial.println("PWM Value set to: " + String(pwmValue));
}

void initiateDoubleBlink() {
  isBlinking = true;          // Start blinking
  blinkCount = 0;             // Reset blink count
  isLedOn = false;            // Ensure LED starts from OFF state
  digitalWrite(indicatorLedPin, LOW); // Turn LED OFF initially
  lastBlinkMillis = millis(); // Reset the blink timer
}

void handleIndicatorLedBlink() {
  unsigned long currentMillis = millis();

  if (isBlinking) {
    // Check if it's time to toggle the LED state
    if (currentMillis - lastBlinkMillis >= blinkDuration) {
      if (!isLedOn) {
        // Turn LED ON
        digitalWrite(indicatorLedPin, HIGH);
        isLedOn = true;
      } else {
        // Turn LED OFF
        digitalWrite(indicatorLedPin, LOW);
        isLedOn = false;
        blinkCount++; // Completed one blink (ON then OFF)

        // Check if the desired number of blinks is reached
        if (blinkCount >= totalBlinks) {
          isBlinking = false; // Stop blinking
        }
      }
      lastBlinkMillis = currentMillis; // Reset the blink timer
    }
  }
}


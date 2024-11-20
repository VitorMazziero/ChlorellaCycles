#include "BluetoothSerial.h" // Include the Bluetooth Serial library
#include <esp_bt_main.h>     // ESP32 Bluetooth headers
#include <esp_bt_device.h>

BluetoothSerial SerialBT; // Create a Bluetooth Serial object

void setup() {
  Serial.begin(115200); // Start the serial communication
  while (!Serial) {
    delay(10); // Wait for the Serial to initialize
  }

  SerialBT.begin("ESP32_BT"); // Initialize Bluetooth with a device name
  Serial.println("Bluetooth initialized. Discovering MAC address...");

  // Get the MAC address of the ESP32's Bluetooth
  const uint8_t* macAddress = esp_bt_dev_get_address();
  if (macAddress) {
    Serial.print("ESP32 Bluetooth MAC Address: ");
    for (int i = 0; i < 6; i++) {
      Serial.printf("%02X", macAddress[i]);
      if (i < 5) Serial.print(":");
    }
    Serial.println();
  } else {
    Serial.println("Failed to retrieve MAC address!");
  }
}

void loop() {
  // Nothing to do here
}

# ChlorellaCycles
App to control LED intensity over time for algae cultivation

## Repository Structure
- **esp32_code**: Contains the ESP32 code for controlling the LED light and MAC adress finder.
- **flutter_app**: Contains the Flutter code for the mobile application.

## Getting Started
### Prerequisites
- ESP32 board
- Flutter environment setup
- Bluetooth-enabled mobile device

#### How to Use the MAC Address Finder:
1. Open `bluetooth_MAC.ino` in the Arduino IDE or your preferred editor.
2. Connect your ESP32 to your computer via USB.
3. Select the correct **Board** and **Port** in the Arduino IDE.
4. Upload the script to the ESP32.
5. Open the **Serial Monitor** and set the baud rate to `115200`.
6. The ESP32 MAC address will be displayed in the Serial Monitor

### How to Run
1. Upload the ESP32 code in the `esp32_code` folder to your ESP32 board.
2. Install and run the Flutter app from the `flutter_app` directory (use the available apk or copy the `main.dart` to the `lib` folder of a new flutter project on Android Studio or your preferred editor).
3. Replace the `pubspec.yaml` for the dependencies and `AndroidManifest.xml` for the necessary Android permissions.
4. Pair your mobile device with the ESP32 (AlgaApp_BT) via Bluetooth.
5. Monitor and control the light intensity using the app.

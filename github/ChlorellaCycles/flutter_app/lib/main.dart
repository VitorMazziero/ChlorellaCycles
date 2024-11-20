import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  double currentLightIntensity = 0; // Default value for light intensity

  void updateLightIntensity(double intensity) {
    setState(() {
      currentLightIntensity = intensity;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MainPage(
        currentLightIntensity: currentLightIntensity,
        onIntensityChanged: updateLightIntensity,
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  final double currentLightIntensity;
  final Function(double) onIntensityChanged;

  MainPage({required this.currentLightIntensity, required this.onIntensityChanged});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  BluetoothConnection? _connection;
  bool isConnecting = false;
  bool isConnected = false;
  List<double> times = [];
  List<double> intensities = [];

  bool isTransitionEnabled = false;
  double maxIntensity = 0;
  double onHours = 12;
  double offHours = 12;
  double dataIntervalMinutes = 1.0; // Default value

  double lastReceivedTime = 0.0;
  double lastReceivedIntensity = 0.0;
  double initialTime = 0.0; // Variable to store the initial time

  // Range slider values for graph scaling
  RangeValues xRange = RangeValues(0, 72); // Adjusted to display up to 72 hours

  // Define the ESP32 MAC address and device name
  final String esp32MACAddress = 'CC:7B:5C:28:8D:A2';
  final String esp32DeviceName = 'AlgaApp_BT';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Load data from SharedPreferences
  void _loadData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    setState(() {
      // Load variables
      isTransitionEnabled = prefs.getBool('isTransitionEnabled') ?? false;
      maxIntensity = prefs.getDouble('maxIntensity') ?? 0;
      onHours = prefs.getDouble('onHours') ?? 12;
      offHours = prefs.getDouble('offHours') ?? 12;
      dataIntervalMinutes = prefs.getDouble('dataIntervalMinutes') ?? 1.0;
      initialTime = prefs.getDouble('initialTime') ?? 0.0; // Load initialTime

      // Load times and intensities
      List<String>? timesStringList = prefs.getStringList('times');
      List<String>? intensitiesStringList = prefs.getStringList('intensities');

      if (timesStringList != null && intensitiesStringList != null) {
        times = timesStringList.map((e) => double.parse(e)).toList();
        intensities = intensitiesStringList.map((e) => double.parse(e)).toList();
      }

      // Update the background color based on the last intensity
      if (intensities.isNotEmpty) {
        double lastIntensity = intensities.last;
        widget.onIntensityChanged(lastIntensity);
        lastReceivedIntensity = lastIntensity;
      }
      else {
        widget.onIntensityChanged(maxIntensity);
      }
      // Update lastReceivedTime
      if (times.isNotEmpty) {
        double lastTime = times.last;
        lastReceivedTime = lastTime;
      }
    });
  }

  // Save data to SharedPreferences
  void _saveData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Save variables
    prefs.setBool('isTransitionEnabled', isTransitionEnabled);
    prefs.setDouble('maxIntensity', maxIntensity);
    prefs.setDouble('onHours', onHours);
    prefs.setDouble('offHours', offHours);
    prefs.setDouble('dataIntervalMinutes', dataIntervalMinutes);
    prefs.setDouble('initialTime', initialTime); // Save initialTime

    // Save times and intensities
    List<String> timesStringList = times.map((e) => e.toString()).toList();
    List<String> intensitiesStringList = intensities.map((e) => e.toString()).toList();

    prefs.setStringList('times', timesStringList);
    prefs.setStringList('intensities', intensitiesStringList);
  }

  void _connectToDevice() async {
    if (isConnected || isConnecting) {
      return;
    }
    try {
      setState(() {
        isConnecting = true;
      });
      _connection = await BluetoothConnection.toAddress(esp32MACAddress);
      setState(() {
        isConnecting = false;
        isConnected = true;
      });
      _connection!.input!.listen(_onDataReceived).onDone(() {
        setState(() {
          isConnected = false;
        });
      });
    } catch (e) {
      print('Error: $e');
      setState(() {
        isConnecting = false;
        isConnected = false;
      });
    }
  }

  void _disconnect() async {
    await _connection?.close();
    setState(() {
      isConnected = false;
    });
  }

  String _buffer = '';
  void _onDataReceived(Uint8List data) {
    String receivedData = String.fromCharCodes(data);
    _buffer += receivedData;

    int index;
    // Assuming that messages are terminated with a newline character '\n'
    while ((index = _buffer.indexOf('\n')) != -1) {
      String message = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);
      try {
        Map<String, dynamic> parsedData = jsonDecode(message);
        setState(() {
          double timeMinutes = (parsedData['time'] ?? 0.0).toDouble();
          double time = timeMinutes / 60.0; // Convert to hours
          double intensity = (parsedData['intensity'] ?? 0.0).toDouble();
          double on = (parsedData['on'] ?? 12.0);
          double off = (parsedData['off'] ?? 12.0);
          double interval = (parsedData['interval'] ?? 1.0).toDouble();
          int transition = (parsedData['transition'] ?? 0);

          // Set initialTime when the first data point is received
          if (initialTime == 0.0) {
            initialTime = time;
            _saveData(); // Save initialTime
          }

          double adjustedTime = time - initialTime;

          times.add(adjustedTime);
          intensities.add(intensity);
          widget.onIntensityChanged(intensity); // Update intensity for theme

          // Update state variables
          lastReceivedTime = adjustedTime;
          lastReceivedIntensity = intensity;
          onHours = on.toDouble();
          offHours = off.toDouble();
          dataIntervalMinutes = interval;
          isTransitionEnabled = transition == 1;
          maxIntensity = intensity; // Update the slider to match the received intensity

          // Save data after receiving new data
          _saveData();
        });
      } catch (e) {
        print('Error parsing data: $e');
        // Optionally, you can also print the message that caused the error
        print('Failed message: $message');
      }
    }
  }

  void _sendData() {
    // Prepare the data in the required format
    final data = {
      "intensity": maxIntensity.toInt(),
      "on": onHours,
      "off": offHours,
      "interval": dataIntervalMinutes,
      "transition": isTransitionEnabled ? 1 : 0,
    };
    String jsonData = jsonEncode(data);
    _connection?.output.add(Uint8List.fromList(utf8.encode(jsonData + '\n')));
    print('Sending data: $jsonData');
  }

  Color getDynamicTextColor(double intensity) {
    if (intensity <= 50) {
      return Color.lerp(Colors.white, Colors.black, intensity / 10) ?? Colors.white;
    } else {
      return Colors.black;
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Color> gradientColors = _getBackgroundGradientColors(widget.currentLightIntensity);
    Color backgroundColor = gradientColors.first.withOpacity(0.05);
    Color textColor = getDynamicTextColor(widget.currentLightIntensity);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
          ),
        ),
        child: SizedBox.expand(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 32.0, left: 16.0, right: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Chlorella App',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    IconButton(
                      icon: Icon(
                        isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                        color: isConnected ? Colors.green : textColor,
                      ),
                      onPressed: () {
                        if (isConnected) {
                          _disconnect();
                        } else {
                          _connectToDevice();
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildMonitorCard(backgroundColor, textColor),
                    const SizedBox(height: 10),
                    _buildCombinedCard(backgroundColor, textColor),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _getBackgroundGradientColors(double intensity) {
    Color startColor =
        Color.lerp(const Color(0xFF05113A), Colors.lightBlueAccent, intensity / 70) ?? Colors.black;
    Color endColor = Color.lerp(Colors.blue, Colors.lightBlue[100], intensity / 30) ?? Colors.blue;
    return [startColor, endColor];
  }

  String formatElapsedTime(double timeInHours) {
    int totalMinutes = (timeInHours * 60).round();
    int hours = totalMinutes ~/ 60; // Integer division to get hours
    int minutes = totalMinutes % 60; // Remainder to get remaining minutes

    if (hours >= 100) {
      // Special formatting for very large hours values (hundreds or more)
      return '${hours}h ${minutes}m';
    } else {
      // Standard HH:MM formatting for up to 99 hours
      return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m';
    }
  }

  // Generate simulated data
  List<FlSpot> generateSimulatedData(double minX, double maxX) {
    double cycleDuration = onHours + offHours;
    List<FlSpot> simulatedData = [];

    // Simulate from 0 to 72h, or maxX + 24h, whichever is larger
    double simulationEnd = max(72.0, maxX + 24.0);

    for (double t = minX; t <= simulationEnd; t += dataIntervalMinutes / 60.0) {
      double cyclePosition = t % cycleDuration;
      double intensity = (cyclePosition < onHours) ? maxIntensity : 0.0;
      simulatedData.add(FlSpot(t, intensity));
    }
    return simulatedData;
  }

  Widget _buildMonitorCard(Color backgroundColor, Color textColor) {
    double minX = 0.0;
    double dataMaxX = times.isNotEmpty ? times.last + 5.0 : 1.0; // Add 5 to the last data point's time

    // Simulate up to 72h or dataMaxX + 24h
    double simulationEnd = max(72.0, dataMaxX + 24.0);

    double maxX = simulationEnd;

    // Generate simulated data
    List<FlSpot> simulatedData = generateSimulatedData(minX, maxX);

    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Existing Row with Title and Clear Graph button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Light Intensity Monitor',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                // Clear Graph Button
                TextButton(
                  onPressed: () {
                    setState(() {
                      times.clear();
                      intensities.clear();
                      initialTime = 0.0; // Reset initialTime
                      // Reset xRange to initial values
                      xRange = RangeValues(0, 24); // Set default range after clearing
                      _saveData();
                    });
                  },
                  child: Text(
                    'Clear Graph',
                    style: TextStyle(color: textColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: true),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        axisNameWidget: Padding(
                          padding: const EdgeInsets.only(bottom: 0.0),
                          child: Text(
                            'Intensity (%)',
                            style: TextStyle(color: textColor, fontSize: 12),
                          ),
                        ),
                        sideTitles: const SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        axisNameWidget: Padding(
                          padding: const EdgeInsets.only(top: 1.0),
                          child: Text(
                            'Time (h)',
                            style: TextStyle(color: textColor, fontSize: 12),
                          ),
                        ),
                        sideTitles: const SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 25,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Text(
                                value.toInt().toString(),
                                style: TextStyle(color: textColor, fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: Text(
                                value.toStringAsFixed(1),
                                style: TextStyle(color: textColor, fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(border: Border.all(color: textColor)),
                    minY: 0,
                    maxY: 100,
                    minX: xRange.start,
                    maxX: xRange.end,
                    clipData: FlClipData.all(), // Ensure data is contained within the graph
                    lineBarsData: [
                      // Simulated data as a line
                      LineChartBarData(
                        spots: simulatedData,
                        isCurved: false,
                        color: Colors.lightGreen, // Choose a color for the simulated line
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: FlDotData(show: false), // Hide dots
                        belowBarData: BarAreaData(show: false),
                      ),
                      // Actual data points as dots
                      LineChartBarData(
                        spots: List.generate(
                          times.length,
                              (index) => FlSpot(times[index], intensities[index]),
                        ),
                        isCurved: true,
                        color: textColor,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: FlDotData(show: true), // Show dots connected by lines
                      ),
                    ],
                  ),
                ),
              ),
            ),
            RangeSlider(
              values: xRange,
              min: minX,
              max: maxX, // Updated max to include simulated data
              divisions: 100, // Increase divisions for better scaling
              labels: RangeLabels(
                'Min: ${xRange.start.toStringAsFixed(1)}',
                'Max: ${xRange.end.toStringAsFixed(1)}',
              ),
              onChanged: (RangeValues values) {
                setState(() {
                  xRange = values;
                  _saveData();
                });
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Elapsed Time: ${formatElapsedTime(lastReceivedTime)}',
                  style: TextStyle(color: textColor),
                ),
                Text(
                  'Current Intensity: ${lastReceivedIntensity.toStringAsFixed(0)}%',
                  style: TextStyle(color: textColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedCard(Color backgroundColor, Color textColor) {
    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Light Intensity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            Row(
              children: [
                Text('Transition', style: TextStyle(color: textColor)),
                Switch(
                  value: isTransitionEnabled,
                  onChanged: (value) {
                    setState(() {
                      isTransitionEnabled = value;
                      _saveData();
                    });
                  },
                ),
                Spacer(),
                ElevatedButton(
                  onPressed: isConnected ? _sendData : null,
                  child: const Text('Send'),
                ),
              ],
            ),
            Slider(
              value: maxIntensity,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${maxIntensity.toStringAsFixed(0)}%',
              onChanged: (value) {
                setState(() {
                  maxIntensity = value;
                  widget.onIntensityChanged(value);
                  _saveData();
                });
              },
            ),
            const SizedBox(height: 20),
            // Interval Field
            Text('Data Interval (minutes): ${dataIntervalMinutes.toStringAsFixed(1)}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            Slider(
              value: dataIntervalMinutes,
              min: 0.5,
              max: 60,
              divisions: 600, // Allows decimal precision
              label: '${dataIntervalMinutes.toStringAsFixed(1)} min',
              onChanged: (value) {
                setState(() {
                  dataIntervalMinutes = value;
                  _saveData();
                });
              },
            ),
            const SizedBox(height: 20),
            Text('Light Cycles',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 10),
            Text('ON cycle: ${onHours.toStringAsFixed(1)}h', style: TextStyle(color: textColor)),
            Slider(
              value: onHours,
              min: 0,
              max: 24,
              divisions: 240, // Allows decimal precision
              label: '${onHours.toStringAsFixed(1)}h',
              onChanged: (value) {
                setState(() {
                  onHours = value;
                  offHours = 24 - onHours;
                  _saveData();
                });
              },
            ),
            Text('OFF cycle: ${offHours.toStringAsFixed(1)}h', style: TextStyle(color: textColor)),
            Slider(
              value: offHours,
              min: 0,
              max: 24,
              divisions: 240, // Allows decimal precision
              label: '${offHours.toStringAsFixed(1)}h',
              onChanged: (value) {
                setState(() {
                  offHours = value;
                  onHours = 24 - offHours;
                  _saveData();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

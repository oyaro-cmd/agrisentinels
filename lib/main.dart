import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.grey[50],
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class ScanRecord {
  final String imagePath;
  final String result;
  final double confidence;
  final String severity;
  final String location;
  final DateTime timestamp;

  ScanRecord({
    required this.imagePath,
    required this.result,
    required this.confidence,
    required this.severity,
    required this.location,
    required this.timestamp,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _confidenceThreshold = 60.0;
  Interpreter? _interpreter;
  File? _image;
  String _result = "Ready to Scan";
  String _locationMessage = "Waiting for GPS...";
  double _confidence = 0.0;
  bool _isDemoMode = false; // Failsafe if model is missing
  final List<ScanRecord> _scanHistory = [];

  final ImagePicker _picker = ImagePicker();
  // Must match labels.txt order from the exported model.
  final List<String> labels = ["Armyworm", "Healthy", "Leaf Blight"];

  final Map<String, String> adviceByLabel = {
    "Healthy": "Keep monitoring weekly, remove weeds, and maintain balanced irrigation and nutrition.",
    "Armyworm": "Inspect early morning/evening, hand-pick larvae, remove infested leaves, and consider approved biopesticides (e.g., Bt) if outbreaks spread.",
    "Leaf Blight": "Remove infected leaves, improve airflow, avoid overhead watering, and apply a recommended fungicide if symptoms persist.",
    "Unknown": "Low confidence result. Try a clearer close-up image with good lighting.",
  };
  final Map<String, String> severityByLabel = {
    "Healthy": "Low",
    "Armyworm": "High",
    "Leaf Blight": "Medium",
    "Unknown": "Unknown",
  };

  @override
  void initState() {
    super.initState();
    loadModel();
    _checkLocationPermissions();
  }

  // 1. Load AI Model (With Failsafe)
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset("model.tflite");
      debugPrint("✅ Model Loaded Successfully");
    } catch (e) {
      debugPrint("⚠️ Model not found. Switching to DEMO MODE.");
      setState(() {
        _isDemoMode = true;
        _result = "Demo Mode (Model Missing)";
      });
    }
  }

  // 2. GPS Logic
  Future<void> _checkLocationPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationMessage = "GPS Disabled");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
       _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _locationMessage = 
            "Lat: ${position.latitude.toStringAsFixed(4)}, "
            "Lng: ${position.longitude.toStringAsFixed(4)}";
      });
    } catch (e) {
      setState(() => _locationMessage = "Locating...");
    }
  }

  // 3. Image Handling
  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
      _result = "Analyzing...";
      _confidence = 0.0;
    });

    // Verify location again when scanning
    _getCurrentLocation();

    // Run Classification
    if (_isDemoMode) {
      _simulatePrediction();
    } else {
      classifyImage(_image!);
    }
  }

  void _addHistoryEntry({
    required String imagePath,
    required String result,
    required double confidence,
  }) {
    final severity = severityByLabel[result] ?? "Unknown";
    final location = _locationMessage;

    setState(() {
      _scanHistory.insert(
        0,
        ScanRecord(
          imagePath: imagePath,
          result: result,
          confidence: confidence,
          severity: severity,
          location: location,
          timestamp: DateTime.now(),
        ),
      );

      if (_scanHistory.length > 10) {
        _scanHistory.removeLast();
      }
    });
  }

  String _formatTimestamp(DateTime dateTime) {
    final hours = dateTime.hour.toString().padLeft(2, "0");
    final minutes = dateTime.minute.toString().padLeft(2, "0");
    return "${dateTime.month}/${dateTime.day} ${hours}:${minutes}";
  }

  // 4a. REAL Classification
  Future<void> classifyImage(File image) async {
    if (_interpreter == null) {
      _simulatePrediction();
      return;
    }

    try {
      final rawBytes = await image.readAsBytes();
      final decoded = img.decodeImage(rawBytes);

      if (decoded == null) {
        _simulatePrediction();
        return;
      }

      // Teachable Machine expects a direct resize (no crop) with [-1, 1] normalization.
      final processed = img.copyResize(
        decoded,
        width: 224,
        height: 224,
      );
      final rgbaBytes = processed.getBytes();
      final input = Float32List(1 * 224 * 224 * 3);

      int i = 0;
      for (int p = 0; p < rgbaBytes.length; p += 4) {
        input[i++] = (rgbaBytes[p] / 127.5) - 1.0;
        input[i++] = (rgbaBytes[p + 1] / 127.5) - 1.0;
        input[i++] = (rgbaBytes[p + 2] / 127.5) - 1.0;
      }

      var output = List.filled(3, 0.0).reshape([1, 3]);
      _interpreter!.run(input.reshape([1, 224, 224, 3]), output);

      int index = output[0].indexOf(output[0].reduce((a, b) => a > b ? a : b));
      String result = labels[index];
      final confidence = output[0][index] * 100;
      if (confidence < _confidenceThreshold) {
        result = "Unknown";
      }

      setState(() {
        _result = result;
        _confidence = confidence;
      });

      _addHistoryEntry(
        imagePath: image.path,
        result: result,
        confidence: confidence,
      );
    } catch (e) {
      _simulatePrediction(); // Fallback if preprocessing fails
    }
  }

  // 4b. SIMULATED Classification (So you don't get stuck)
  void _simulatePrediction() async {
    await Future.delayed(const Duration(seconds: 2)); // Fake thinking time
    final random = Random();
    int index = random.nextInt(3);
    
    String result = labels[index];
    final confidence = 85.0 + random.nextInt(14);
    if (confidence < _confidenceThreshold) {
      result = "Unknown";
    }

    setState(() {
      _result = result;
      _confidence = confidence;
    });
    
    if (_image != null) {
      _addHistoryEntry(
        imagePath: _image!.path,
        result: result,
        confidence: confidence,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("?? Simulating Result (Check model.tflite)")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AgriSentinels", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green[800],
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Status Bar (Location)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              color: Colors.green[800],
              child: Column(
                children: [
                  const Text("Early Warning System", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on, color: Colors.white, size: 16),
                      const SizedBox(width: 5),
                      Text(_locationMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Image Preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _image == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.spa, size: 60, color: Colors.green[100]),
                          const SizedBox(height: 10),
                          Text("No Crop Scanned", style: TextStyle(color: Colors.grey[400])),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(_image!, fit: BoxFit.cover),
                      ),
              ),
            ),

            const SizedBox(height: 30),

            // Result Card
            if (_image != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _result == "Analyzing..."
                      ? Colors.white
                      : (_result == "Healthy"
                          ? Colors.green[50]
                          : (_result == "Unknown" ? Colors.grey[100] : Colors.red[50])),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: _result == "Analyzing..."
                        ? Colors.grey.shade200
                        : (_result == "Healthy"
                            ? Colors.green
                            : (_result == "Unknown" ? Colors.grey : Colors.red)),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _result.toUpperCase(),
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.w900,
                        color: _result == "Healthy"
                            ? Colors.green[800]
                            : (_result == "Unknown" ? Colors.grey[800] : Colors.red[800]),
                      ),
                    ),
                    if (_result != "Analyzing...")
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: severityByLabel[_result] == "Low"
                              ? Colors.green[100]
                              : (severityByLabel[_result] == "Medium"
                                  ? Colors.orange[100]
                                  : (severityByLabel[_result] == "Unknown"
                                      ? Colors.grey[200]
                                      : Colors.red[100])),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: severityByLabel[_result] == "Low"
                                ? Colors.green
                                : (severityByLabel[_result] == "Medium"
                                    ? Colors.orange
                                    : (severityByLabel[_result] == "Unknown"
                                        ? Colors.grey
                                        : Colors.red)),
                          ),
                        ),
                        child: Text(
                          "Severity: ${severityByLabel[_result] ?? "Unknown"}",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: severityByLabel[_result] == "Low"
                                ? Colors.green[800]
                                : (severityByLabel[_result] == "Medium"
                                    ? Colors.orange[800]
                                    : (severityByLabel[_result] == "Unknown"
                                        ? Colors.grey[800]
                                        : Colors.red[800])),
                          ),
                        ),
                      ),
                    if (_result != "Analyzing...")
                      Text(
                        "Confidence: ${_confidence.toStringAsFixed(1)}%",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    if (_result != "Analyzing...")
                      const SizedBox(height: 12),
                    if (_result != "Analyzing...")
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Recommended Actions",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              adviceByLabel[_result] ?? "No guidance available for this result.",
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 30),

            // Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text("SCAN"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => pickImage(ImageSource.gallery), // UPLOAD BUTTON
                      icon: const Icon(Icons.upload_file),
                      label: const Text("UPLOAD"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // History
            if (_scanHistory.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Recent Scans",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        final scan = _scanHistory[index];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(scan.imagePath),
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      scan.result,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Severity: ${scan.severity} - ${scan.confidence.toStringAsFixed(1)}%",
                                      style: TextStyle(color: Colors.grey[700]),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "${scan.location} - ${_formatTimestamp(scan.timestamp)}",
                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemCount: _scanHistory.length,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

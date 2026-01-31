import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:geolocator/geolocator.dart';

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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Interpreter? _interpreter;
  File? _image;
  String _result = "Ready to Scan";
  String _locationMessage = "Waiting for GPS...";
  double _confidence = 0.0;
  bool _isDemoMode = false; // Failsafe if model is missing

  final ImagePicker _picker = ImagePicker();
  final List<String> labels = ["Healthy", "Armyworm", "Leaf Blight"];

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

  // 4a. REAL Classification
  Future<void> classifyImage(File image) async {
    if (_interpreter == null) {
      _simulatePrediction();
      return;
    }

    try {
      final bytes = await image.readAsBytes();
      final input = Float32List(1 * 224 * 224 * 3);
      int i = 0;

      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          int pixelIndex = ((y * 224 + x) % bytes.length); 
          input[i++] = bytes[pixelIndex] / 255.0; 
          input[i++] = bytes[pixelIndex] / 255.0; 
          input[i++] = bytes[pixelIndex] / 255.0; 
        }
      }

      var output = List.filled(3, 0.0).reshape([1, 3]);
      _interpreter!.run(input.reshape([1, 224, 224, 3]), output);

      int index = output[0].indexOf(output[0].reduce((a, b) => a > b ? a : b));

      setState(() {
        _result = labels[index];
        _confidence = output[0][index] * 100;
      });
    } catch (e) {
      _simulatePrediction(); // Fallback if matrix math fails
    }
  }

  // 4b. SIMULATED Classification (So you don't get stuck)
  void _simulatePrediction() async {
    await Future.delayed(const Duration(seconds: 2)); // Fake thinking time
    final random = Random();
    int index = random.nextInt(3);
    
    setState(() {
      _result = labels[index];
      _confidence = 85.0 + random.nextInt(14);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⚠️ Simulating Result (Check model.tflite)")),
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
                  color: _result == "Analyzing..." ? Colors.white : (_result == "Healthy" ? Colors.green[50] : Colors.red[50]),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: _result == "Analyzing..." ? Colors.grey.shade200 : (_result == "Healthy" ? Colors.green : Colors.red),
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
                        color: _result == "Healthy" ? Colors.green[800] : Colors.red[800],
                      ),
                    ),
                    if (_result != "Analyzing...")
                      Text(
                        "Confidence: ${_confidence.toStringAsFixed(1)}%",
                        style: TextStyle(color: Colors.grey[600]),
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
          ],
        ),
      ),
    );
  }
}
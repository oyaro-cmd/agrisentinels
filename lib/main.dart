import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  Map<String, dynamic> toMap() {
    return {
      "imagePath": imagePath,
      "result": result,
      "confidence": confidence,
      "severity": severity,
      "location": location,
      "timestamp": timestamp.toIso8601String(),
    };
  }

  factory ScanRecord.fromMap(Map<String, dynamic> map) {
    return ScanRecord(
      imagePath: map["imagePath"] as String? ?? "",
      result: map["result"] as String? ?? "Unknown",
      confidence: (map["confidence"] as num?)?.toDouble() ?? 0.0,
      severity: map["severity"] as String? ?? "Unknown",
      location: map["location"] as String? ?? "Unknown",
      timestamp: DateTime.tryParse(map["timestamp"] as String? ?? "") ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _Score {
  final String label;
  final double score;
  _Score(this.label, this.score);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _confidenceThreshold = 60.0;
  static const String _historyStorageKey = "scan_history_v1";

  Interpreter? _interpreter;
  File? _image;
  String _result = "Ready to Scan";
  String _locationMessage = "Waiting for GPS...";
  double _confidence = 0.0;
  List<_Score> _top3 = [];
  String? _modelLoadError;
  final List<ScanRecord> _scanHistory = [];
  final ImagePicker _picker = ImagePicker();

  List<String> _labels = const ["Armyworm", "Healthy", "Leaf Blight"];

  final Map<String, String> adviceByLabel = {
    "Healthy": "Keep monitoring weekly, remove weeds, and maintain balanced irrigation and nutrition.",
    "Armyworm": "Inspect early morning/evening, hand-pick larvae, remove infested leaves, and consider approved biopesticides (e.g., Bt) if outbreaks spread.",
    "Leaf Blight": "Remove infected leaves, improve airflow, avoid overhead watering, and apply a recommended fungicide if symptoms persist.",
    "Unknown": "Low confidence result. Try a clearer close-up image with good lighting.",
    "Model Error": "Model could not be loaded. Replace model.tflite and labels.txt from the same export, then restart the app.",
    "Inference Error": "Image analysis failed. Try a clear close-up image and ensure model files are valid.",
  };

  final Map<String, String> severityByLabel = {
    "Healthy": "Low",
    "Armyworm": "High",
    "Leaf Blight": "Medium",
    "Unknown": "Unknown",
    "Model Error": "Unknown",
    "Inference Error": "Unknown",
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
    loadModel();
    _checkLocationPermissions();
  }

  // ✅ FIX 1: Added dispose() — was completely missing, leaked native TFLite memory
  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  // ✅ FIX 2: split("\n") — was split("\\n") which is literal backslash-n, never splits a real file
  // ✅ FIX 3: RegExp(r"^\d+\s+(.*)$") — was r"^\\d+\\s+..." which double-escapes inside a raw string
  // Your labels.txt uses "0 armyworm" format so the regex MUST strip that number prefix
  Future<List<String>> _loadLabelsFromAsset() async {
    final raw = await rootBundle.loadString("assets/labels.txt");
    final parsed = <String>[];

    for (final line in raw.split("\n")) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final match = RegExp(r"^\d+\s+(.*)$").firstMatch(trimmed);
      final label = (match?.group(1) ?? trimmed).trim();
      parsed.add(_toDisplayLabel(label));
    }

    if (parsed.isEmpty) throw StateError("labels.txt is empty");
    return parsed;
  }

  String _toDisplayLabel(String label) {
    final cleaned = label.replaceAll(RegExp(r"[_-]+"), " ").toLowerCase();
    return cleaned
        .split(" ")
        .where((part) => part.isNotEmpty)
        .map((part) => "${part[0].toUpperCase()}${part.substring(1)}")
        .join(" ");
  }

  List<double> _softmax(List<double> values) {
    final maxValue = values.reduce(max);
    final expValues = values.map((v) => exp(v - maxValue)).toList();
    final sumExp = expValues.fold<double>(0, (a, b) => a + b);
    return expValues.map((v) => v / sumExp).toList();
  }

  List<double> _ensureProbabilities(List<double> scores) {
    final inRange = scores.every((v) => v >= 0.0 && v <= 1.0);
    final sum = scores.fold<double>(0, (a, b) => a + b);
    if (inRange && (sum - 1.0).abs() <= 0.05) return scores;
    return _softmax(scores);
  }

  int _quantizeToInt(
      double value, double scale, int zeroPoint, int min, int max) {
    if (scale == 0) return value.round().clamp(min, max);
    return (value / scale + zeroPoint).round().clamp(min, max);
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyStorageKey);
    if (raw == null || raw.isEmpty) return;

    final decoded = jsonDecode(raw) as List<dynamic>;
    final restored = decoded
        .map((e) => ScanRecord.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    if (!mounted) return;
    setState(() {
      _scanHistory
        ..clear()
        ..addAll(restored);
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final payload =
        jsonEncode(_scanHistory.map((e) => e.toMap()).toList());
    await prefs.setString(_historyStorageKey, payload);
  }

  Future<void> loadModel() async {
    try {
      final loadedLabels = await _loadLabelsFromAsset();
      _interpreter = await Interpreter.fromAsset("assets/model.tflite");

      final outputTensor = _interpreter!.getOutputTensor(0);
      final classCount = outputTensor.shape.last;

      if (loadedLabels.length != classCount) {
        throw StateError(
          "labels count (${loadedLabels.length}) does not match model output ($classCount)",
        );
      }

      setState(() {
        _labels = loadedLabels;
        _modelLoadError = null;
      });

      // ✅ DEBUG — remove before release
      final inputTensor = _interpreter!.getInputTensor(0);
      debugPrint("✅ Labels: $_labels");
      debugPrint("✅ Input shape: ${inputTensor.shape}"); // expect [1, 224, 224, 3]
      debugPrint("✅ Input type:  ${inputTensor.type}");  // expect float32

    } catch (e) {
      _interpreter = null;
      const message =
          "Model load failed. Ensure assets/model.tflite and assets/labels.txt are from the same export.";
      debugPrint("$message Error: $e");
      setState(() {
        _modelLoadError = "$message Error: $e";
        _result = "Model Error";
        _confidence = 0.0;
        _top3 = [];
      });
    }
  }

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

    // ✅ FIX 4: Handle deniedForever — was silently ignored before
    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationMessage = "Location permanently denied");
      return;
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
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

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
      _result = "Analyzing...";
      _confidence = 0.0;
      _top3 = [];
    });

    _getCurrentLocation();

    if (_interpreter == null) {
      _handleInferenceFailure(
        _modelLoadError ??
            "Model unavailable. Replace assets/model.tflite and assets/labels.txt, then restart.",
        resultLabel: "Model Error",
      );
      return;
    }

    // ✅ FIX 5: await was missing — caused race condition on fast double-taps
    await classifyImage(_image!);
  }

  void _addHistoryEntry({
    required String imagePath,
    required String result,
    required double confidence,
  }) {
    setState(() {
      _scanHistory.insert(
        0,
        ScanRecord(
          imagePath: imagePath,
          result: result,
          confidence: confidence,
          severity: severityByLabel[result] ?? "Unknown",
          location: _locationMessage,
          timestamp: DateTime.now(),
        ),
      );
      if (_scanHistory.length > 10) _scanHistory.removeLast();
    });
    _saveHistory();
  }

  String _formatTimestamp(DateTime dt) {
    return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}";
  }

  void _handleInferenceFailure(String message,
      {String resultLabel = "Inference Error"}) {
    debugPrint(message);
    if (!mounted) return;
    setState(() {
      _result = resultLabel;
      _confidence = 0.0;
      _top3 = [];
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Object _buildInputTensorData(
    Uint8List rgbaBytes,
    TensorType inputType,
    QuantizationParams inputParams,
    int width,
    int height,
  ) {
    if (inputType == TensorType.float32) {
      final input = Float32List(width * height * 3);
      int i = 0;
      for (int p = 0; p < rgbaBytes.length; p += 4) {
        input[i++] = (rgbaBytes[p] / 127.5) - 1.0;
        input[i++] = (rgbaBytes[p + 1] / 127.5) - 1.0;
        input[i++] = (rgbaBytes[p + 2] / 127.5) - 1.0;
      }
      return input.reshape([1, height, width, 3]);
    }

    if (inputType == TensorType.uint8) {
      final input = Uint8List(width * height * 3);
      int i = 0;
      for (int p = 0; p < rgbaBytes.length; p += 4) {
        final r = (rgbaBytes[p] / 127.5) - 1.0;
        final g = (rgbaBytes[p + 1] / 127.5) - 1.0;
        final b = (rgbaBytes[p + 2] / 127.5) - 1.0;
        input[i++] = _quantizeToInt(r, inputParams.scale, inputParams.zeroPoint, 0, 255);
        input[i++] = _quantizeToInt(g, inputParams.scale, inputParams.zeroPoint, 0, 255);
        input[i++] = _quantizeToInt(b, inputParams.scale, inputParams.zeroPoint, 0, 255);
      }
      return input.reshape([1, height, width, 3]);
    }

    if (inputType == TensorType.int8) {
      final input = Int8List(width * height * 3);
      int i = 0;
      for (int p = 0; p < rgbaBytes.length; p += 4) {
        final r = (rgbaBytes[p] / 127.5) - 1.0;
        final g = (rgbaBytes[p + 1] / 127.5) - 1.0;
        final b = (rgbaBytes[p + 2] / 127.5) - 1.0;
        input[i++] = _quantizeToInt(r, inputParams.scale, inputParams.zeroPoint, -128, 127);
        input[i++] = _quantizeToInt(g, inputParams.scale, inputParams.zeroPoint, -128, 127);
        input[i++] = _quantizeToInt(b, inputParams.scale, inputParams.zeroPoint, -128, 127);
      }
      return input.reshape([1, height, width, 3]);
    }

    throw UnsupportedError("Unsupported input tensor type: $inputType");
  }

  List<double> _readOutputScores(
    TensorType outputType,
    QuantizationParams outputParams,
    Object outputBuffer,
  ) {
    if (outputType == TensorType.float32) {
      return _ensureProbabilities(
          List<double>.from((outputBuffer as List)[0]));
    }
    if (outputType == TensorType.uint8) {
      final q = List<int>.from((outputBuffer as List)[0]);
      return _ensureProbabilities(q
          .map((v) => outputParams.scale == 0
              ? v.toDouble()
              : (v - outputParams.zeroPoint) * outputParams.scale)
          .toList());
    }
    if (outputType == TensorType.int8) {
      final q = List<int>.from((outputBuffer as List)[0]);
      return _ensureProbabilities(q
          .map((v) => outputParams.scale == 0
              ? v.toDouble()
              : (v - outputParams.zeroPoint) * outputParams.scale)
          .toList());
    }
    throw UnsupportedError("Unsupported output tensor type: $outputType");
  }

  List<_Score> _buildTop3(List<double> scores) {
    final all = <_Score>[];
    final count = min(scores.length, _labels.length);
    for (int i = 0; i < count; i++) {
      all.add(_Score(_labels[i], scores[i] * 100));
    }
    all.sort((a, b) => b.score.compareTo(a.score));
    return all.take(3).toList();
  }

  Future<void> classifyImage(File image) async {
    if (_interpreter == null) {
      _handleInferenceFailure(
        _modelLoadError ?? "Model unavailable.",
        resultLabel: "Model Error",
      );
      return;
    }

    try {
      final rawBytes = await image.readAsBytes();
      final decoded = img.decodeImage(rawBytes);

      if (decoded == null) {
        _handleInferenceFailure("Could not decode image. Try a different one.");
        return;
      }

      final inputTensor = _interpreter!.getInputTensor(0);
      final inputShape = inputTensor.shape;
      if (inputShape.length < 4 || inputShape[3] != 3) {
        throw StateError("Unexpected input tensor shape: $inputShape");
      }
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];

      // ✅ FIX 6: Center-crop to square before resize — matches Teachable Machine webcam framing
      // Without this, portrait/landscape images get squashed and distort features
      final minDim = min(decoded.width, decoded.height);
      final cropped = img.copyCrop(
        decoded,
        x: (decoded.width - minDim) ~/ 2,
        y: (decoded.height - minDim) ~/ 2,
        width: minDim,
        height: minDim,
      );
      final processed = img.copyResize(
        cropped,
        width: inputWidth,
        height: inputHeight,
        interpolation: img.Interpolation.linear,
      );

      // ✅ FIX 7: image v4.1.7 uses ChannelOrder enum, NOT Format enum
      // img.Format.rgba would be a compile error in this version
      final rgbaBytes = processed.getBytes(order: img.ChannelOrder.rgba);

      final inputData = _buildInputTensorData(
        rgbaBytes,
        inputTensor.type,
        inputTensor.params,
        inputWidth,
        inputHeight,
      );

      final outputTensor = _interpreter!.getOutputTensor(0);
      final classCount = outputTensor.shape.last;
      final outputBuffer = outputTensor.type == TensorType.float32
          ? List.filled(classCount, 0.0).reshape([1, classCount])
          : List.filled(classCount, 0).reshape([1, classCount]);

      _interpreter!.run(inputData, outputBuffer);

      final probabilities = _readOutputScores(
        outputTensor.type,
        outputTensor.params,
        outputBuffer,
      );

      final index = probabilities
          .indexOf(probabilities.reduce((a, b) => a > b ? a : b));
      final confidence = probabilities[index] * 100;
      final top3 = _buildTop3(probabilities);
      final result =
          confidence < _confidenceThreshold ? "Unknown" : _labels[index];

      setState(() {
        _result = result;
        _confidence = confidence;
        _top3 = top3;
      });

      _addHistoryEntry(
        imagePath: image.path,
        result: result,
        confidence: confidence,
      );
    } catch (e) {
      _handleInferenceFailure("Image analysis failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AgriSentinels",
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green[800],
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              color: Colors.green[800],
              child: Column(
                children: [
                  const Text("Early Warning System",
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 5),
                      Text(_locationMessage,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5))
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _image == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.spa, size: 60, color: Colors.green[100]),
                          const SizedBox(height: 10),
                          Text("No Crop Scanned",
                              style: TextStyle(color: Colors.grey[400])),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(_image!, fit: BoxFit.cover),
                      ),
              ),
            ),

            const SizedBox(height: 30),

            if (_image != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _result == "Analyzing..."
                      ? Colors.white
                      : (_result == "Healthy"
                          ? Colors.green[50]
                          : (_result == "Unknown"
                              ? Colors.grey[100]
                              : Colors.red[50])),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: _result == "Analyzing..."
                        ? Colors.grey.shade200
                        : (_result == "Healthy"
                            ? Colors.green
                            : (_result == "Unknown"
                                ? Colors.grey
                                : Colors.red)),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    // ✅ FIX 8: Spinner while analyzing — was just text before
                    if (_result == "Analyzing...")
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(color: Colors.green),
                      ),

                    Text(
                      _result.toUpperCase(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _result == "Healthy"
                            ? Colors.green[800]
                            : (_result == "Unknown"
                                ? Colors.grey[800]
                                : Colors.red[800]),
                      ),
                    ),

                    if (_result != "Analyzing...")
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
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

                    if (_result != "Analyzing..." && _top3.isNotEmpty)
                      const SizedBox(height: 8),

                    if (_result != "Analyzing..." && _top3.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Top 3 Predictions",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            for (final score in _top3)
                              Text(
                                "${score.label}: ${score.score.toStringAsFixed(1)}%",
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                          ],
                        ),
                      ),

                    if (_result != "Analyzing...") const SizedBox(height: 12),

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
                            const Text("Recommended Actions",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(
                              adviceByLabel[_result] ??
                                  "No guidance available.",
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 30),

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
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.upload_file),
                      label: const Text("UPLOAD"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            if (_scanHistory.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Recent Scans",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _scanHistory.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                                color: Colors.black.withValues(alpha: 0.05),
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
                                    Text(scan.result,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Severity: ${scan.severity} - ${scan.confidence.toStringAsFixed(1)}%",
                                      style:
                                          TextStyle(color: Colors.grey[700]),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "${scan.location} - ${_formatTimestamp(scan.timestamp)}",
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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

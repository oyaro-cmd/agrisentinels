import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Static helpers for shared_preferences access
  static const String storageKey = "scan_history_v1";

  static Future<List<ScanRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => ScanRecord.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> saveAll(List<ScanRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(records.map((e) => e.toMap()).toList());
    await prefs.setString(storageKey, payload);
  }
}

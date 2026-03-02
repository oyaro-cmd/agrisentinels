import 'package:flutter_test/flutter_test.dart';

import 'package:agrisentinel_demo/main.dart';

void main() {
  test('ScanRecord serializes and deserializes consistently', () {
    final timestamp = DateTime.utc(2026, 2, 24, 10, 30, 0);
    final record = ScanRecord(
      imagePath: 'C:/tmp/leaf.jpg',
      result: 'Leaf Blight',
      confidence: 82.5,
      severity: 'Medium',
      location: 'Lat: -1.2864, Lng: 36.8172',
      timestamp: timestamp,
    );

    final map = record.toMap();
    final restored = ScanRecord.fromMap(map);

    expect(restored.imagePath, record.imagePath);
    expect(restored.result, record.result);
    expect(restored.confidence, record.confidence);
    expect(restored.severity, record.severity);
    expect(restored.location, record.location);
    expect(restored.timestamp, record.timestamp);
  });

  test('ScanRecord.fromMap applies safe defaults for missing fields', () {
    final restored = ScanRecord.fromMap({});

    expect(restored.imagePath, '');
    expect(restored.result, 'Unknown');
    expect(restored.confidence, 0.0);
    expect(restored.severity, 'Unknown');
    expect(restored.location, 'Unknown');
  });
}

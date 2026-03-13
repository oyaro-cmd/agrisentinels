import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:latlong2/latlong.dart';
import 'models.dart';

class HeatmapPage extends StatefulWidget {
  const HeatmapPage({super.key});

  @override
  State<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends State<HeatmapPage> {
  List<WeightedLatLng> _heatPoints = [];
  List<ScanRecord> _allScans = [];
  bool _loading = true;
  DateTime? _lastUpdated;

  final MapController _mapController = MapController();

  static const LatLng _kenyaCenter = LatLng(-1.286389, 36.817223);

  // ✅ FIXED: use MaterialColor, no const
  static final Map<double, MaterialColor> _heatGradient = {
    0.25: Colors.green,
    0.55: Colors.yellow,
    0.75: Colors.orange,
    1.0:  Colors.red,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  double _severityWeight(String severity) {
    switch (severity) {
      case "High":   return 1.0;
      case "Medium": return 0.6;
      case "Low":    return 0.2;
      default:       return 0.1;
    }
  }

  LatLng? _parseLocation(String location) {
    final match = RegExp(
      r"Lat:\s*([\d.\-]+),\s*Lng:\s*([\d.\-]+)",
    ).firstMatch(location);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1) ?? "");
    final lng = double.tryParse(match.group(2) ?? "");
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final scans = await ScanRecord.loadAll();
    final points = <WeightedLatLng>[];

    for (final scan in scans) {
      final latLng = _parseLocation(scan.location);
      if (latLng == null) continue;
      points.add(WeightedLatLng(latLng, _severityWeight(scan.severity)));
    }

    if (!mounted) return;
    setState(() {
      _allScans = scans;
      _heatPoints = points;
      _lastUpdated = DateTime.now();
      _loading = false;
    });
  }

  int get _highSeverityCount =>
      _allScans.where((s) => s.severity == "High" &&
          _parseLocation(s.location) != null).length;

  int get _plottedCount => _heatPoints.length;

  String _formatLastUpdated() {
    if (_lastUpdated == null) return "Never";
    final dt = _lastUpdated!;
    return "${dt.hour.toString().padLeft(2, "0")}:"
        "${dt.minute.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Outbreak Heatmap",
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green[800],
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: "Refresh",
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.green))
          : Stack(
              children: [
                _heatPoints.isEmpty
                    ? _buildEmptyState()
                    : FlutterMap(
                        mapController: _mapController,
                        options: const MapOptions(
                          initialCenter: _kenyaCenter,
                          initialZoom: 6.0,
                          minZoom: 3.0,
                          maxZoom: 18.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                            userAgentPackageName:
                                "com.example.agrisentinel_demo",
                          ),
                          HeatMapLayer(
                            heatMapDataSource:
                                InMemoryHeatMapDataSource(
                                    data: _heatPoints),
                            heatMapOptions: HeatMapOptions(
                              gradient: _heatGradient,
                              minOpacity: 0.4,
                              radius: 40,
                            ),
                          ),
                        ],
                      ),

                // ── Info Panel ────────────────────────────────
                if (_heatPoints.isNotEmpty)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.93),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                        children: [
                          _buildInfoChip(
                            icon: Icons.location_on,
                            label: "Points",
                            value: "$_plottedCount",
                            color: Colors.green[700]!,
                          ),
                          _buildInfoDivider(),
                          _buildInfoChip(
                            icon: Icons.warning_amber_rounded,
                            label: "High Risk",
                            value: "$_highSeverityCount",
                            color: Colors.red,
                          ),
                          _buildInfoDivider(),
                          _buildInfoChip(
                            icon: Icons.access_time,
                            label: "Updated",
                            value: _formatLastUpdated(),
                            color: Colors.grey[600]!,
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Legend ─────────────────────────────────────
                if (_heatPoints.isNotEmpty)
                  Positioned(
                    bottom: 24,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.93),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Severity",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.grey[700])),
                          const SizedBox(height: 6),
                          _buildLegendItem(
                              Colors.red, "High (Armyworm)"),
                          _buildLegendItem(
                              Colors.orange, "Medium (Leaf Blight)"),
                          _buildLegendItem(
                              Colors.green, "Low (Healthy)"),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: color)),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildInfoDivider() {
    return Container(
      height: 36,
      width: 1,
      color: Colors.grey.shade200,
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined,
                size: 80, color: Colors.green[100]),
            const SizedBox(height: 20),
            const Text(
              "No GPS-tagged scans yet",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              "Scan crops in the field with GPS enabled to populate the outbreak map.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], height: 1.5),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.camera_alt),
              label: const Text("Go Scan Crops"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

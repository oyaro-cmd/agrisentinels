import 'dart:io';
import 'package:flutter/material.dart';
import 'models.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<ScanRecord> _allScans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadScans();
  }

  Future<void> _loadScans() async {
    final scans = await ScanRecord.loadAll();
    if (!mounted) return;
    setState(() {
      _allScans = scans;
      _loading = false;
    });
  }

  // ── Computed Stats ──────────────────────────────────────────
  int get _totalScans => _allScans.length;

  int _countByResult(String result) =>
      _allScans.where((s) => s.result == result).length;

  double _percentByResult(String result) {
    if (_totalScans == 0) return 0;
    return (_countByResult(result) / _totalScans) * 100;
  }

  List<ScanRecord> get _recentScans => _allScans.take(5).toList();

  List<ScanRecord> get _highSeverityThisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _allScans
        .where((s) =>
            s.severity == "High" && s.timestamp.isAfter(cutoff))
        .toList();
  }

  double get _avgConfidence {
    if (_totalScans == 0) return 0;
    final sum = _allScans.fold<double>(0, (a, b) => a + b.confidence);
    return sum / _totalScans;
  }

  String _formatDate(DateTime dt) {
    const months = [
      "Jan","Feb","Mar","Apr","May","Jun",
      "Jul","Aug","Sep","Oct","Nov","Dec"
    ];
    const days = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
    return "${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day} ${dt.year}";
  }

  String _formatTimestamp(DateTime dt) {
    return "${dt.month}/${dt.day} "
        "${dt.hour.toString().padLeft(2, "0")}:"
        "${dt.minute.toString().padLeft(2, "0")}";
  }

  // ── UI Helpers ───────────────────────────────────────────────
  Color _severityColor(String severity) {
    switch (severity) {
      case "High":   return Colors.red;
      case "Medium": return Colors.orange;
      case "Low":    return Colors.green;
      default:       return Colors.grey;
    }
  }

  Color _resultColor(String result) {
    switch (result) {
      case "Healthy":     return Colors.green;
      case "Armyworm":    return Colors.red;
      case "Leaf Blight": return Colors.orange;
      default:            return Colors.grey;
    }
  }

  IconData _resultIcon(String result) {
    switch (result) {
      case "Healthy":     return Icons.check_circle;
      case "Armyworm":    return Icons.bug_report;
      case "Leaf Blight": return Icons.local_florist;
      default:            return Icons.help_outline;
    }
  }

  // ── Widget Builders ──────────────────────────────────────────
  Widget _buildStatCard(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(
              "$count",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownBar(String label, String result) {
    final percent = _percentByResult(result);
    final color = _resultColor(result);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(_resultIcon(result), color: color, size: 14),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
              Text(
                "${_countByResult(result)} (${percent.toStringAsFixed(0)}%)",
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard(ScanRecord scan) {
    final color = _resultColor(scan.result);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: scan.imagePath.isNotEmpty
                ? Image.file(
                    File(scan.imagePath),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderThumb(color),
                  )
                : _placeholderThumb(color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_resultIcon(scan.result), color: color, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      scan.result,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: color),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _severityColor(scan.severity)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: _severityColor(scan.severity)
                                .withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        scan.severity,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _severityColor(scan.severity),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  "${scan.confidence.toStringAsFixed(1)}% confidence",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.location_on,
                        size: 11, color: Colors.grey[400]),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        scan.location,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 11),
                      ),
                    ),
                    Text(
                      _formatTimestamp(scan.timestamp),
                      style:
                          TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderThumb(Color color) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.image_not_supported, color: color, size: 24),
    );
  }

  // ── Main Build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          "Dashboard",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green[800],
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadScans,
            tooltip: "Refresh",
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.green))
          : _totalScans == 0
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadScans,
                  color: Colors.green,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date
                        Text(
                          _formatDate(DateTime.now()),
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Farm Overview",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.grey[800],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Alert Banner ──────────────────────────
                        if (_highSeverityThisWeek.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: Colors.red, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "${_highSeverityThisWeek.length} high-severity detection"
                                    "${_highSeverityThisWeek.length > 1 ? "s" : ""} "
                                    "in the last 7 days. Inspect your crops immediately.",
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // ── Stat Cards ────────────────────────────
                        Row(
                          children: [
                            _buildStatCard("Armyworm",
                                _countByResult("Armyworm"),
                                Colors.red,
                                Icons.bug_report),
                            const SizedBox(width: 10),
                            _buildStatCard("Leaf Blight",
                                _countByResult("Leaf Blight"),
                                Colors.orange,
                                Icons.local_florist),
                            const SizedBox(width: 10),
                            _buildStatCard("Healthy",
                                _countByResult("Healthy"),
                                Colors.green,
                                Icons.check_circle),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // ── Summary Row ───────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text("Total Scans",
                                        style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Text(
                                      "$_totalScans",
                                      style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text("Avg Confidence",
                                        style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Text(
                                      "${_avgConfidence.toStringAsFixed(1)}%",
                                      style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ── Disease Breakdown ─────────────────────
                        const Text(
                          "Disease Breakdown",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              _buildBreakdownBar("Armyworm", "Armyworm"),
                              _buildBreakdownBar(
                                  "Leaf Blight", "Leaf Blight"),
                              _buildBreakdownBar("Healthy", "Healthy"),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Recent Scans ──────────────────────────
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Recent Activity",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800),
                            ),
                            Text(
                              "${_recentScans.length} of $_totalScans",
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._recentScans.map(_buildScanCard),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 72, color: Colors.green[100]),
          const SizedBox(height: 16),
          const Text(
            "No scans yet",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            "Go back and scan your first crop\nto see dashboard stats here.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

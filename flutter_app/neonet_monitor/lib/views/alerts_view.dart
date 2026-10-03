import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AlertsView extends StatefulWidget {
  const AlertsView({super.key});

  @override
  State<AlertsView> createState() => _AlertsViewState();
}

class _AlertsViewState extends State<AlertsView> {
  Timer? _timer;
  bool isOnline = false;

  // Flow Variables for Leak Detection
  double flowA1 = 0.0;
  double flowA2 = 0.0;
  double flowB1 = 0.0;
  double flowB2 = 0.0;
  static const double leakThreshold = 5.0;

  // Water Quality Variables
  String turbStatus = "AWAITING DATA";
  String tdsStatus = "AWAITING DATA";
  int tdsPPM = 0;

  @override
  void initState() {
    super.initState();
    // Poll the ESP32 for active conditions
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _fetchAlertData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAlertData() async {
    try {
      final response = await http.get(Uri.parse('http://192.168.4.1/data'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          flowA1 = (data['flow_a1'] ?? 0.0 as num).toDouble();
          flowA2 = (data['flow_a2'] ?? 0.0 as num).toDouble();
          flowB1 = (data['flow_b1'] ?? data['flow_2_1'] ?? 0.0 as num).toDouble();
          flowB2 = (data['flow_b2'] ?? data['flow_2_2'] ?? 0.0 as num).toDouble();

          turbStatus = (data['turbidity_status'] ?? 'AWAITING DATA') as String;
          tdsStatus = (data['tds_status'] ?? 'AWAITING DATA') as String;
          tdsPPM = (data['tds_ppm'] ?? 0 as num).toInt();

          isOnline = true;
        });
      }
    } catch (e) {
      setState(() {
        isOnline = false;
      });
    }
  }

  // Generate dynamic alert rows based on current system conditions
  List<DataRow> _generateActiveAlerts() {
    List<DataRow> rows = [];
    String timeNow = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";

    if (!isOnline) {
      rows.add(_buildAlertRow('SYS-ERR', timeNow, 'CORE-ESP32', 'CRITICAL', 'Connection lost to main sensor hub', const Color(0xFFFF1744)));
      return rows;
    }

    // 1. Leak Detection: Branch A
    if (flowA1 > 0 && (flowA1 - flowA2) > leakThreshold) {
      double loss = flowA1 - flowA2;
      rows.add(_buildAlertRow('LEAK-A', timeNow, 'FS-02 / FS-03', 'CRITICAL', 'Pipeline leakage detected in Branch A: -${loss.toStringAsFixed(1)} mL/s', const Color(0xFFFF1744)));
    }

    // 2. Leak Detection: Branch B
    if (flowB1 > 0 && (flowB1 - flowB2) > leakThreshold) {
      double loss = flowB1 - flowB2;
      rows.add(_buildAlertRow('LEAK-B', timeNow, 'FS-04 / FS-05', 'CRITICAL', 'Pipeline leakage detected in Branch B: -${loss.toStringAsFixed(1)} mL/s', const Color(0xFFFF1744)));
    }

    // 3. Water Quality: Turbidity
    if (turbStatus == 'SLIGHTLY TURBID') {
      rows.add(_buildAlertRow('WQ-TURB', timeNow, 'SN-001', 'WARNING', 'Turbidity elevated: Slightly Turbid water detected', const Color(0xFFFFB300)));
    } else if (turbStatus == 'HIGHLY TURBID') {
      rows.add(_buildAlertRow('WQ-TURB', timeNow, 'SN-001', 'CRITICAL', 'Turbidity critical: Highly Turbid water detected', const Color(0xFFFF1744)));
    }

    // 4. Water Quality: TDS / PPM
    if (tdsStatus == 'FAIR') {
      rows.add(_buildAlertRow('WQ-TDS', timeNow, 'SN-002', 'WARNING', 'Conductivity warning: Water quality is FAIR ($tdsPPM ppm)', const Color(0xFFFFB300)));
    } else if (tdsStatus == 'POOR') {
      rows.add(_buildAlertRow('WQ-TDS', timeNow, 'SN-002', 'CRITICAL', 'Conductivity critical: Water quality is POOR ($tdsPPM ppm)', const Color(0xFFFF1744)));
    }

    // 5. System Nominal Fallback
    if (rows.isEmpty && isOnline) {
      rows.add(_buildAlertRow('SYS-OK', timeNow, 'ALL-NODES', 'NOMINAL', 'System operating within normal parameters. No active alerts.', const Color(0xFF00E676)));
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ALERT SYSTEM MONITOR LOG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1722),
                border: Border.all(color: const Color(0xFF162535)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF09111A)),
                  columns: const [
                    DataColumn(label: Text('ID', style: TextStyle(color: Colors.grey))),
                    DataColumn(label: Text('TIMESTAMP', style: TextStyle(color: Colors.grey))),
                    DataColumn(label: Text('NODE SENSOR', style: TextStyle(color: Colors.grey))),
                    DataColumn(label: Text('SEVERITY', style: TextStyle(color: Colors.grey))),
                    DataColumn(label: Text('LOG TRANSMISSION MESSAGE', style: TextStyle(color: Colors.grey))),
                  ],
                  rows: _generateActiveAlerts(),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  DataRow _buildAlertRow(String id, String time, String sensor, String severity, String msg, Color severityColor) {
    return DataRow(
      cells: [
        DataCell(Text(id, style: const TextStyle(fontFamily: 'monospace', color: Colors.blueGrey))),
        DataCell(Text(time, style: const TextStyle(fontFamily: 'monospace'))),
        DataCell(Text(sensor, style: const TextStyle(color: Color(0xFF00A3FF), fontWeight: FontWeight.bold))),
        DataCell(Row(
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: severityColor, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(severity, style: TextStyle(color: severityColor, fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        )),
        DataCell(Text(msg, style: TextStyle(color: severityColor == const Color(0xFF00E676) ? Colors.blueGrey : Colors.white))),
      ],
    );
  }
}
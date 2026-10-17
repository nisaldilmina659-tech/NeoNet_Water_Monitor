import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class AlertsView extends StatefulWidget {
  const AlertsView({super.key});

  @override
  State<AlertsView> createState() => _AlertsViewState();
}

class _AlertsViewState extends State<AlertsView> {
  StreamSubscription<DatabaseEvent>? _sensorSub;
  StreamSubscription<DatabaseEvent>? _alertsSub; // NEW: Listener for saved alerts
  bool isOnline = false;

  double flowA1 = 0.0;
  double flowA2 = 0.0;
  double flowB1 = 0.0;
  double flowB2 = 0.0;
  static const double leakThreshold = 5.0;

  String turbStatus = "AWAITING DATA";
  String tdsStatus = "AWAITING DATA";
  int tdsPPM = 0;

  // This list now mirrors the permanent database in Firebase
  List<Map<String, dynamic>> _persistentAlerts = [];

  @override
  void initState() {
    super.initState();
    _setupFirebaseListener();
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _alertsSub?.cancel();
    super.dispose();
  }

  void _setupFirebaseListener() {
    final db = FirebaseDatabase.instance.ref();

    // 1. Listen to permanently saved alerts from Firebase
    _alertsSub = db.child('alerts').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        List<Map<String, dynamic>> tempAlerts = [];

        data.forEach((key, value) {
          var alertData = Map<String, dynamic>.from(value as Map);
          alertData['key'] = key; // Save the unique database ID so we can delete it later
          tempAlerts.add(alertData);
        });

        // Sort so the newest alerts appear at the top
        tempAlerts.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

        if (mounted) {
          setState(() {
            _persistentAlerts = tempAlerts;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _persistentAlerts = [];
          });
        }
      }
    });

    // 2. Listen to live sensors to trigger alerts
    _sensorSub = db.child('sensors/current').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);

        setState(() {
          flowA1 = (data['flow_a1'] ?? 0.0).toDouble();
          flowA2 = (data['flow_a2'] ?? 0.0).toDouble();
          flowB1 = (data['flow_b1'] ?? 0.0).toDouble();
          flowB2 = (data['flow_b2'] ?? 0.0).toDouble();
          turbStatus = (data['turbidity_status'] ?? 'AWAITING DATA').toString();
          tdsStatus = (data['tds_status'] ?? 'AWAITING DATA').toString();
          tdsPPM = (data['tds_ppm'] ?? 0).toInt();
          isOnline = true;

          _evaluatePersistentAlerts();
        });
      }
    }, onError: (error) {
      setState(() => isOnline = false);
    });
  }

  void _evaluatePersistentAlerts() {
    // Restored the missing subtraction operators (-)
    bool isLeakingA = flowA1 > 0 && (flowA1 - flowA2) > leakThreshold;
    if (isLeakingA && !_alertExists('LEAK-A')) {
      double loss = flowA1 - flowA2;
      _addAlertToLog('LEAK-A', 'FS-02 / FS-03', 'CRITICAL', 'Pipeline leakage detected in Branch A: -${loss.toStringAsFixed(1)} mL/s', const Color(0xFFFF1744));
    }

    bool isLeakingB = flowB1 > 0 && (flowB1 - flowB2) > leakThreshold;
    if (isLeakingB && !_alertExists('LEAK-B')) {
      double loss = flowB1 - flowB2;
      _addAlertToLog('LEAK-B', 'FS-04 / FS-05', 'CRITICAL', 'Pipeline leakage detected in Branch B: -${loss.toStringAsFixed(1)} mL/s', const Color(0xFFFF1744));
    }

    if (turbStatus == 'HIGHLY TURBID' && !_alertExists('WQ-TURB-HIGH')) {
      _addAlertToLog('WQ-TURB-HIGH', 'SN-001', 'CRITICAL', 'Turbidity critical: Highly Turbid water detected', const Color(0xFFFF1744));
    }
  }

  bool _alertExists(String id) {
    return _persistentAlerts.any((alert) => alert['id'] == id);
  }

  void _addAlertToLog(String id, String sensor, String severity, String msg, Color severityColor) {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    // PUSH TO FIREBASE: This permanently saves the alert to the database
    FirebaseDatabase.instance.ref().child('alerts').push().set({
      'id': id,
      'date': dateStr,
      'time': timeStr,
      'sensor': sensor,
      'severity': severity,
      'msg': msg,
      'color': severityColor.value, // Save color as an integer
      'timestamp': ServerValue.timestamp, // Server time for accurate sorting
    });
  }

  void _dismissAlert(String key) {
    // REMOVE FROM FIREBASE: Deletes the alert forever when operator clicks INSPECT
    FirebaseDatabase.instance.ref().child('alerts/$key').remove();
  }

  List<DataRow> _generateTableRows() {
    List<DataRow> rows = [];

    if (!isOnline) {
      rows.add(_buildSingleRow(
        id: 'SYS-ERR',
        dateTimeWidget: const Text('--:--', style: TextStyle(color: Colors.redAccent)),
        sensor: 'CORE-ESP32',
        severity: 'CRITICAL',
        msg: 'Connection lost to main sensor hub',
        severityColor: const Color(0xFFFF1744),
        actionWidget: const SizedBox(),
      ));
      return rows;
    }

    if (_persistentAlerts.isEmpty) {
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

      rows.add(_buildSingleRow(
        id: 'SYS-OK',
        dateTimeWidget: Text(
            "$dateStr   $timeStr",
            style: const TextStyle(color: Colors.blueGrey, fontFamily: 'monospace')
        ),
        sensor: 'ALL-NODES',
        severity: 'NOMINAL',
        msg: 'System operating within normal parameters. All branches cleared.',
        severityColor: const Color(0xFF00E676),
        actionWidget: const SizedBox(),
      ));
      return rows;
    }

    // Map the database alerts into the table UI
    for (int i = 0; i < _persistentAlerts.length; i++) {
      var alert = _persistentAlerts[i];
      rows.add(
          _buildSingleRow(
            id: alert['id'],
            dateTimeWidget: Text(
              "${alert['date']}   ${alert['time']}",
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
            sensor: alert['sensor'],
            severity: alert['severity'],
            msg: alert['msg'],
            severityColor: Color(alert['color'] as int), // Restore the saved color
            actionWidget: TextButton.icon(
              // Trigger deletion from Firebase using the unique key
              onPressed: () => _dismissAlert(alert['key']),
              icon: const Icon(Icons.playlist_add_check_circle_rounded, color: Colors.greenAccent, size: 18),
              label: const Text("INSPECT", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          )
      );
    }

    return rows;
  }

  DataRow _buildSingleRow({required String id, required Widget dateTimeWidget, required String sensor, required String severity, required String msg, required Color severityColor, required Widget actionWidget}) {
    return DataRow(
      cells: [
        DataCell(Text(id, style: const TextStyle(fontFamily: 'monospace', color: Colors.blueGrey))),
        DataCell(dateTimeWidget),
        DataCell(Text(sensor, style: const TextStyle(color: Color(0xFF00A3FF), fontWeight: FontWeight.bold))),
        DataCell(Row(
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: severityColor, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(severity, style: TextStyle(color: severityColor, fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        )),
        DataCell(Text(msg, style: TextStyle(color: severityColor == const Color(0xFF00E676) ? Colors.blueGrey : Colors.white))),
        DataCell(actionWidget),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PIPELINE INSPECTION & ALERT LOGS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          const Text('Alerts are securely logged to the cloud and remain visible until physically inspected and cleared by an operator.', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
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
                    DataColumn(label: Text('DATE & TIME', style: TextStyle(color: Colors.grey))),
                    DataColumn(label: Text('NODE SENSOR', style: TextStyle(color: Colors.grey))),
                    DataColumn(label: Text('SEVERITY', style: TextStyle(color: Colors.grey))),
                    DataColumn(label: Text('LOG TRANSMISSION MESSAGE', style: TextStyle(color: Colors.grey))),
                    DataColumn(label: Text('ACTION', style: TextStyle(color: Colors.grey))),
                  ],
                  rows: _generateTableRows(),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
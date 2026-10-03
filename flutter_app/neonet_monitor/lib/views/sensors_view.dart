import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SensorsView extends StatefulWidget {
  const SensorsView({super.key});

  @override
  State<SensorsView> createState() => _SensorsViewState();
}

class _SensorsViewState extends State<SensorsView> {
  Timer? _timer;
  bool isOnline = false;

  double flowMainMLs = 0.0, totalVolumeLiters = 0.0;
  double flowA1MLs = 0.0, flowA2MLs = 0.0;
  double flowB1MLs = 0.0, flowB2MLs = 0.0;
  static const double leakThreshold = 5.0;

  int turbADC = 0, tdsADC = 0, tdsPPM = 0;
  String turbStatus = "AWAITING DATA", tdsStatus = "AWAITING DATA";

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _fetchLiveData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLiveData() async {
    try {
      final response = await http.get(Uri.parse('http://192.168.4.1/data'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          flowMainMLs = (data['flow_main'] ?? 0.0 as num).toDouble();
          totalVolumeLiters = (data['total_l'] ?? 0.0 as num).toDouble();
          flowA1MLs = (data['flow_a1'] ?? 0.0 as num).toDouble();
          flowA2MLs = (data['flow_a2'] ?? 0.0 as num).toDouble();
          flowB1MLs = (data['flow_b1'] ?? 0.0 as num).toDouble();
          flowB2MLs = (data['flow_b2'] ?? 0.0 as num).toDouble();
          turbADC = (data['turbidity_adc'] ?? 0 as num).toInt();
          turbStatus = (data['turbidity_status'] ?? 'AWAITING DATA') as String;
          tdsADC = (data['tds_adc'] ?? 0 as num).toInt();
          tdsPPM = (data['tds_ppm'] ?? 0 as num).toInt();
          tdsStatus = (data['tds_status'] ?? 'AWAITING DATA') as String;
          isOnline = true;
        });
      }
    } catch (e) {
      setState(() => isOnline = false);
    }
  }

  bool get isBranchALeaking => isOnline && flowA1MLs > 0 && (flowA1MLs - flowA2MLs) > leakThreshold;
  bool get isBranchBLeaking => isOnline && flowB1MLs > 0 && (flowB1MLs - flowB2MLs) > leakThreshold;

  String _getTurbidityLabel() => !isOnline ? 'OFFLINE' : (turbStatus == 'CLEAR WATER' ? 'NOMINAL' : 'WARNING');
  Color _getTurbidityColor() => !isOnline ? const Color(0xFFFF1744) : (turbStatus == 'CLEAR WATER' ? const Color(0xFF00E676) : const Color(0xFFFFB300));
  String _getTdsLabel() => !isOnline ? 'OFFLINE' : ((tdsStatus == 'EXCELLENT' || tdsStatus == 'GOOD') ? 'NOMINAL' : 'WARNING');
  Color _getTdsColor() => !isOnline ? const Color(0xFFFF1744) : ((tdsStatus == 'EXCELLENT' || tdsStatus == 'GOOD') ? const Color(0xFF00E676) : const Color(0xFFFFB300));

  @override
  Widget build(BuildContext context) {
    final bool hasActiveLeak = isBranchALeaking || isBranchBLeaking;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ACTIVE SENSOR DATABASE & DISTRIBUTION NETWORK', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: isOnline ? const Color(0xFF00E676) : const Color(0xFFFF1744), shape: BoxShape.circle)), const SizedBox(width: 8), Text(isOnline ? 'LINK ACTIVE' : 'CONNECTION LOST', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))])
              ],
            ),
            const SizedBox(height: 14),

            if (hasActiveLeak)
              Container(
                margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: const Color(0xFFFF1744).withOpacity(0.15), border: Border.all(color: const Color(0xFFFF1744), width: 1.5), borderRadius: BorderRadius.circular(4)),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF1744), size: 24), const SizedBox(width: 12),
                    Expanded(child: Text('PIPELINE INTEGRITY COMPROMISED: ' + [if (isBranchALeaking) 'LEAKAGE DETECTED IN BRANCH A (-${(flowA1MLs - flowA2MLs).toStringAsFixed(1)} mL/s)', if (isBranchBLeaking) 'LEAKAGE DETECTED IN BRANCH B (-${(flowB1MLs - flowB2MLs).toStringAsFixed(1)} mL/s)'].join(' | '), style: const TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold, letterSpacing: 0.5, fontSize: 13))),
                  ],
                ),
              ),

            Expanded(
              child: GridView.count(
                crossAxisCount: 3, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 1.25,
                children: [
                  _buildSensorCard('SN-001: Main Turbidity', 'Turbidity Sensor Module', turbStatus, 'ADC: $turbADC', _getTurbidityLabel(), _getTurbidityColor()),
                  _buildSensorCard('SN-002: Main Conductivity', 'TDS Sensor Module', '$tdsPPM', 'ppm (ADC: $tdsADC)', _getTdsLabel(), _getTdsColor()),
                  _buildSensorCard('SN-003: Cumulative Total', 'Totalized Flow Volume', totalVolumeLiters.toStringAsFixed(3), 'Liters Dispensed', 'TRACKING', const Color(0xFF00A3FF)),
                  _buildSensorCard('FS-01: Main Branch', 'Primary Inflow Header (YF-S201)', flowMainMLs.toStringAsFixed(2), 'mL/s (Main Header)', !isOnline ? 'OFFLINE' : (flowMainMLs > 0 ? 'FLOWING' : 'STANDBY'), !isOnline ? const Color(0xFFFF1744) : (flowMainMLs > 0 ? const Color(0xFF00E676) : const Color(0xFF90A4AE))),
                  _buildBranchFlowCard(branchName: 'Branch A', sensorInletId: 'FS-02 (Inlet)', sensorOutletId: 'FS-03 (Downstream)', inletFlow: flowA1MLs, outletFlow: flowA2MLs, isLeaking: isBranchALeaking),
                  _buildBranchFlowCard(branchName: 'Branch B', sensorInletId: 'FS-04 (Inlet)', sensorOutletId: 'FS-05 (Downstream)', inletFlow: flowB1MLs, outletFlow: flowB2MLs, isLeaking: isBranchBLeaking),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchFlowCard({required String branchName, required String sensorInletId, required String sensorOutletId, required double inletFlow, required double outletFlow, required bool isLeaking}) {
    final double flowDiff = inletFlow - outletFlow;
    final Color stateColor = !isOnline ? const Color(0xFFFF1744) : (isLeaking ? const Color(0xFFFF1744) : (inletFlow > 0 ? const Color(0xFF00E676) : const Color(0xFF90A4AE)));
    final String statusText = !isOnline ? 'OFFLINE' : (isLeaking ? 'LEAK DETECTED' : (inletFlow > 0 ? 'NORMAL FLOW' : 'STANDBY'));

    return Container(
      padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFF0D1722), border: Border.all(color: isLeaking ? const Color(0xFFFF1744) : const Color(0xFF162535), width: isLeaking ? 1.5 : 1.0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('DISTRIBUTION: $branchName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00A3FF))), Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle)), const SizedBox(width: 6), Text(statusText, style: TextStyle(color: stateColor, fontSize: 10, fontWeight: FontWeight.bold))])]),
          const SizedBox(height: 4), Text('Branch Primary ($sensorInletId)', style: const TextStyle(fontSize: 11, color: Colors.grey)), const Spacer(),
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: const Color(0xFF070D14), border: Border.all(color: const Color(0xFF162535)), borderRadius: BorderRadius.circular(4)), child: Column(children: [Text(inletFlow.toStringAsFixed(2), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'monospace')), const SizedBox(height: 2), const Text('mL/s Inflow Rate', style: TextStyle(fontSize: 11, color: Colors.blueGrey))])),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('End Point ($sensorOutletId): ${outletFlow.toStringAsFixed(2)} mL/s', style: const TextStyle(fontSize: 10, color: Colors.blueGrey)), Text(isLeaking ? 'Loss: -${flowDiff.toStringAsFixed(1)} mL/s' : 'Loss: 0.0 mL/s', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLeaking ? const Color(0xFFFF1744) : const Color(0xFF00E676)))])
        ],
      ),
    );
  }

  Widget _buildSensorCard(String id, String type, String value, String unit, String status, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFF0D1722), border: Border.all(color: const Color(0xFF162535))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00A3FF))), Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)), const SizedBox(width: 6), Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold))])]),
          const SizedBox(height: 4), Text(type, style: const TextStyle(fontSize: 11, color: Colors.grey)), const Spacer(),
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: const Color(0xFF070D14), border: Border.all(color: const Color(0xFF162535)), borderRadius: BorderRadius.circular(4)), child: Column(children: [Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'monospace')), const SizedBox(height: 2), Text(unit, style: const TextStyle(fontSize: 11, color: Colors.blueGrey))])),
          const Spacer(), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(isOnline ? 'LAST PING: LIVE' : 'DISCONNECTED', style: const TextStyle(fontSize: 9, color: Colors.blueGrey)), Icon(Icons.memory, size: 16, color: statusColor.withOpacity(0.5))])
        ],
      ),
    );
  }
}
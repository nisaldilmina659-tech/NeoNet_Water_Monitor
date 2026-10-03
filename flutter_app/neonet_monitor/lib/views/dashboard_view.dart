import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  Timer? _timer;
  bool isOnline = false;

  // Live Data Variables
  double flowMain = 0.0, totalVolume = 0.0;
  double flowA1 = 0.0, flowA2 = 0.0;
  double flowB1 = 0.0, flowB2 = 0.0;

  String turbStatus = "AWAITING", tdsStatus = "AWAITING";
  int tdsPPM = 0;
  double tankLevelPercent = 85.0;

  // Valve Control States
  bool isValve1Open = false;
  bool isValve2Open = false;
  bool isTogglingValve1 = false;
  bool isTogglingValve2 = false;

  static const double leakThreshold = 5.0;
  bool get isBranchALeaking => isOnline && flowA1 > 0 && (flowA1 - flowA2) > leakThreshold;
  bool get isBranchBLeaking => isOnline && flowB1 > 0 && (flowB1 - flowB2) > leakThreshold;

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
          flowMain = (data['flow_main'] ?? 0.0 as num).toDouble();
          totalVolume = (data['total_l'] ?? 0.0 as num).toDouble();
          flowA1 = (data['flow_a1'] ?? 0.0 as num).toDouble();
          flowA2 = (data['flow_a2'] ?? 0.0 as num).toDouble();
          flowB1 = (data['flow_b1'] ?? 0.0 as num).toDouble();
          flowB2 = (data['flow_b2'] ?? 0.0 as num).toDouble();
          turbStatus = data['turbidity_status'] ?? 'UNKNOWN';
          tdsStatus = data['tds_status'] ?? 'UNKNOWN';
          tdsPPM = (data['tds_ppm'] ?? 0 as num).toInt();

          if (!isTogglingValve1) isValve1Open = (data['valve1_status'] == 'OPEN');
          if (!isTogglingValve2) isValve2Open = (data['valve2_status'] == 'OPEN');

          isOnline = true;
        });
      }
    } catch (e) {
      setState(() => isOnline = false);
    }
  }

  Future<void> _toggleValve(int id, bool turnOn) async {
    if (id == 1) setState(() => isTogglingValve1 = true);
    else setState(() => isTogglingValve2 = true);

    try {
      String action = turnOn ? 'open' : 'close';
      final response = await http.get(Uri.parse('http://192.168.4.1/valve?id=$id&state=$action'));
      if (response.statusCode == 200) {
        setState(() {
          if (id == 1) isValve1Open = turnOn;
          else isValve2Open = turnOn;
        });
      }
    } catch (e) {
      // Hardware unreachable
    } finally {
      if (id == 1) setState(() => isTogglingValve1 = false);
      else setState(() => isTogglingValve2 = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMetricsRow(),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildDistributionAndControlNetwork()),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: _buildConsumptionGraphPanel()),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(child: _metricCard('CURRENT FLOW RATE', isOnline ? '${flowMain.toStringAsFixed(1)} mL/s' : 'OFFLINE', 'Main Intake Header', const Color(0xFF00A3FF))),
        const SizedBox(width: 12),
        Expanded(child: _metricCard('ACTIVE SENSORS', isOnline ? '5 / 5' : '0 / 5', isOnline ? 'Network Linked' : 'Connection Lost', isOnline ? const Color(0xFF00E676) : const Color(0xFFFF1744))),
        const SizedBox(width: 12),
        Expanded(child: _metricCard('WATER QUALITY', isOnline ? '$tdsPPM ppm' : '---', isOnline ? turbStatus : 'Awaiting Data', (turbStatus == 'CLEAR WATER' && tdsPPM < 600) ? const Color(0xFF00E676) : const Color(0xFFFFB300))),
        const SizedBox(width: 12),
        Expanded(child: _metricCard('TANK VOLUME', isOnline ? '${totalVolume.toStringAsFixed(2)} L' : '---', 'Total Dispensed', Colors.purpleAccent)),
        const SizedBox(width: 12),
        Expanded(child: _metricCard('WATER LEVEL', '$tankLevelPercent %', 'Main Reservoir', Colors.orangeAccent)),
      ],
    );
  }

  Widget _metricCard(String title, String value, String subtitle, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1722),
        border: Border(top: BorderSide(color: accentColor, width: 3), left: const BorderSide(color: Color(0xFF162535)), right: const BorderSide(color: Color(0xFF162535)), bottom: const BorderSide(color: Color(0xFF162535))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _buildDistributionAndControlNetwork() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PIPELINE DISTRIBUTION & CONTROL NETWORK', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
            children: [
              _buildBranchCard('BRANCH A', flowA1, flowA2, isBranchALeaking),
              _buildBranchCard('BRANCH B', flowB1, flowB2, isBranchBLeaking),
              _buildValveCard(1, 'VL-01: Main Header', 'Master Intake Cutoff', isValve1Open, isTogglingValve1),
              _buildValveCard(2, 'VL-02: Distribution', 'Secondary Line Cutoff', isValve2Open, isTogglingValve2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBranchCard(String branchName, double inletFlow, double outletFlow, bool isLeaking) {
    double loss = inletFlow - outletFlow;
    Color statusColor = !isOnline ? const Color(0xFFFF1744) : (isLeaking ? const Color(0xFFFF1744) : (inletFlow > 0 ? const Color(0xFF00E676) : const Color(0xFF90A4AE)));
    String bannerText = !isOnline ? 'SYSTEM OFFLINE' : (isLeaking ? '⚠️️ WARNING: LEAKAGE' : (inletFlow > 0 ? '✅ NORMAL FLOW' : '⏸ SYSTEM STANDBY'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF0D1722),
          border: Border.all(color: isLeaking ? const Color(0xFFFF1744) : const Color(0xFF162535), width: isLeaking ? 2.0 : 1.0),
          boxShadow: [if (isLeaking) BoxShadow(color: const Color(0xFFFF1744).withOpacity(0.2), blurRadius: 15, spreadRadius: 2)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(branchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF00A3FF))),
              Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)), const SizedBox(width: 6), Text(isLeaking ? 'ALERT' : 'ACTIVE', style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold))])
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(color: isOnline ? (isLeaking ? const Color(0xFFFF1744).withOpacity(0.15) : (inletFlow > 0 ? const Color(0xFF00E676).withOpacity(0.1) : const Color(0xFF162535))) : const Color(0xFF162535), borderRadius: BorderRadius.circular(4), border: Border.all(color: isOnline ? (isLeaking ? const Color(0xFFFF1744).withOpacity(0.5) : (inletFlow > 0 ? const Color(0xFF00E676).withOpacity(0.3) : Colors.transparent)) : Colors.transparent)),
            child: Text(bannerText, style: TextStyle(color: !isOnline ? Colors.grey : (isLeaking ? const Color(0xFFFF1744) : (inletFlow > 0 ? const Color(0xFF00E676) : Colors.blueGrey)), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5), textAlign: TextAlign.center),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _flowStat('INLET FLOW', isOnline ? inletFlow.toStringAsFixed(1) : '--'),
              const Icon(Icons.arrow_forward_rounded, color: Colors.blueGrey, size: 20),
              _flowStat('OUTLET FLOW', isOnline ? outletFlow.toStringAsFixed(1) : '--'),
            ],
          ),
          const Spacer(),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: isLeaking ? const Color(0xFFFF1744).withOpacity(0.1) : const Color(0xFF070D14), border: Border.all(color: isLeaking ? const Color(0xFFFF1744).withOpacity(0.5) : const Color(0xFF162535)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              children: [
                Text('VOLUME LOSS DIFFERENTIAL', style: TextStyle(fontSize: 9, color: isLeaking ? const Color(0xFFFF1744) : Colors.blueGrey)),
                const SizedBox(height: 4),
                Text(isOnline ? (isLeaking ? '-${loss.toStringAsFixed(1)} mL/s' : '0.0 mL/s') : '--', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: isLeaking ? const Color(0xFFFF1744) : const Color(0xFF00E676))),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildValveCard(int id, String title, String subtitle, bool isOpen, bool isToggling) {
    Color activeColor = isOnline ? (isOpen ? const Color(0xFF00A3FF) : Colors.blueGrey) : const Color(0xFFFF1744);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1722),
        border: Border.all(color: isOpen ? const Color(0xFF00A3FF).withOpacity(0.5) : const Color(0xFF162535), width: isOpen ? 1.5 : 1.0),
        boxShadow: [if (isOpen && isOnline) BoxShadow(color: const Color(0xFF00A3FF).withOpacity(0.15), blurRadius: 15, spreadRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00A3FF))),
              Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle)), const SizedBox(width: 6), Text(isOnline ? (isOpen ? 'VALVE OPEN' : 'VALVE CLOSED') : 'OFFLINE', style: TextStyle(color: activeColor, fontSize: 10, fontWeight: FontWeight.bold))])
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          Center(
            child: isOnline
                ? Switch(value: isOpen, onChanged: isToggling ? null : (value) => _toggleValve(id, value), activeColor: const Color(0xFF00A3FF), inactiveThumbColor: Colors.blueGrey, inactiveTrackColor: const Color(0xFF070D14))
                : const Icon(Icons.electrical_services_rounded, size: 48, color: Color(0xFFFF1744)),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isToggling ? 'TRANSMITTING...' : (isOnline ? 'READY FOR COMMAND' : 'SYSTEM UNREACHABLE'), style: TextStyle(fontSize: 9, color: isToggling ? const Color(0xFF00A3FF) : Colors.blueGrey)),
              Icon(Icons.settings_remote, size: 16, color: activeColor.withOpacity(0.5)),
            ],
          )
        ],
      ),
    );
  }

  Widget _flowStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.blueGrey)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
          children: [Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace')), const SizedBox(width: 4), const Text('mL/s', style: TextStyle(fontSize: 10, color: Colors.grey))],
        )
      ],
    );
  }

  Widget _buildConsumptionGraphPanel() {
    bool hasAnyLeak = isBranchALeaking || isBranchBLeaking;
    List<String> leakingBranches = [];
    if (isBranchALeaking) leakingBranches.add('Branch A');
    if (isBranchBLeaking) leakingBranches.add('Branch B');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF0D1722), border: Border.all(color: hasAnyLeak ? const Color(0xFFFF1744) : const Color(0xFF162535), width: hasAnyLeak ? 2.0 : 1.0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WATER CONSUMPTION VS. TIME', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          if (hasAnyLeak) ...[
            const SizedBox(height: 12),
            Container(
                width: double.infinity, padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFF1744).withOpacity(0.15), border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.5)), borderRadius: BorderRadius.circular(4)),
                child: Row(children: [const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF1744), size: 18), const SizedBox(width: 8), Expanded(child: Text('CONSUMPTION ANOMALY: Leak detected in ${leakingBranches.join(" & ")}. Graph data may be skewed by unaccounted volume loss.', style: const TextStyle(color: Color(0xFFFF1744), fontSize: 10, fontWeight: FontWeight.bold)))])
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                      spots: const [FlSpot(0, 130), FlSpot(4, 110), FlSpot(8, 340), FlSpot(12, 280), FlSpot(16, 360), FlSpot(20, 210)],
                      isCurved: true, color: hasAnyLeak ? const Color(0xFFFF1744) : const Color(0xFF00A3FF), barWidth: 3, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: (hasAnyLeak ? const Color(0xFFFF1744) : const Color(0xFF00A3FF)).withOpacity(0.1))
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
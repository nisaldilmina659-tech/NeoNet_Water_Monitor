import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  // Firebase Stream Subscriptions
  StreamSubscription<DatabaseEvent>? _sensorSub;
  StreamSubscription<DatabaseEvent>? _historySub;
  StreamSubscription<DatabaseEvent>? _valve1Sub;
  StreamSubscription<DatabaseEvent>? _valve2Sub;
  StreamSubscription<DatabaseEvent>? _autoModeSub;

  bool isOnline = false;

  double flowMain = 0.0, totalVolume = 0.0;
  double flowA1 = 0.0, flowA2 = 0.0;
  double flowB1 = 0.0, flowB2 = 0.0;

  String turbStatus = "AWAITING", tdsStatus = "AWAITING";
  int tdsPPM = 0;
  double tankLevelPercent = 0.0;

  bool isValve1Open = false;
  bool isValve2Open = false;
  bool isTogglingValve1 = false;
  bool isTogglingValve2 = false;

  bool isAutoMode = false;
  bool isTogglingAuto = false;

  List<FlSpot> consumptionSpots = [const FlSpot(0, 0)];

  static const double leakThreshold = 5.0;

  // Restored subtraction operators (-)
  bool get isBranchALeaking => isOnline && flowA1 > 0 && (flowA1 - flowA2) > leakThreshold;
  bool get isBranchBLeaking => isOnline && flowB1 > 0 && (flowB1 - flowB2) > leakThreshold;

  @override
  void initState() {
    super.initState();
    _setupFirebaseListeners();
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _historySub?.cancel();
    _valve1Sub?.cancel();
    _valve2Sub?.cancel();
    _autoModeSub?.cancel();
    super.dispose();
  }

  void _setupFirebaseListeners() {
    final db = FirebaseDatabase.instance.ref();

    _sensorSub = db.child('sensors/current').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() {
          flowMain = (data['flow_main'] ?? 0.0).toDouble();
          totalVolume = (data['total_l'] ?? 0.0).toDouble();
          flowA1 = (data['flow_a1'] ?? 0.0).toDouble();
          flowA2 = (data['flow_a2'] ?? 0.0).toDouble();
          flowB1 = (data['flow_b1'] ?? 0.0).toDouble();
          flowB2 = (data['flow_b2'] ?? 0.0).toDouble();
          turbStatus = (data['turbidity_status'] ?? 'CLEAR WATER').toString();
          tdsStatus = (data['tds_status'] ?? 'GOOD').toString();
          tdsPPM = (data['tds_ppm'] ?? 0).toInt();
          tankLevelPercent = (data['tank_percent'] ?? 0.0).toDouble().clamp(0.0, 100.0);
          isOnline = true;
        });
      }
    }, onError: (error) {
      setState(() => isOnline = false);
    });

    _historySub = db.child('sensors/history').orderByChild('timestamp').limitToLast(20).onValue.listen((event) {
      if (event.snapshot.value != null) {
        final Map<dynamic, dynamic> historyMap = event.snapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> sortedHistory = [];

        historyMap.forEach((key, value) {
          sortedHistory.add(Map<String, dynamic>.from(value as Map));
        });

        sortedHistory.sort((a, b) => ((a['timestamp'] ?? 0) as num).compareTo((b['timestamp'] ?? 0) as num));

        if (sortedHistory.isNotEmpty) {
          List<FlSpot> newSpots = [];
          double baseTime = (sortedHistory.first['timestamp'] ?? 0).toDouble();

          for (var data in sortedHistory) {
            double x = ((data['timestamp'] ?? 0).toDouble() - baseTime) / 60.0;
            double y = (data['flow_main'] ?? 0.0).toDouble();
            newSpots.add(FlSpot(x, y));
          }

          setState(() {
            consumptionSpots = newSpots;
          });
        }
      }
    });

    _valve1Sub = db.child('valves/valve1').onValue.listen((event) {
      if (!isTogglingValve1 && event.snapshot.value != null) {
        setState(() => isValve1Open = (event.snapshot.value.toString() == 'OPEN'));
      }
    });

    _valve2Sub = db.child('valves/valve2').onValue.listen((event) {
      if (!isTogglingValve2 && event.snapshot.value != null) {
        setState(() => isValve2Open = (event.snapshot.value.toString() == 'OPEN'));
      }
    });

    _autoModeSub = db.child('valves/auto_mode').onValue.listen((event) {
      if (!isTogglingAuto && event.snapshot.value != null) {
        setState(() => isAutoMode = (event.snapshot.value.toString() == 'ON'));
      }
    });
  }

  Future<void> _toggleAutoMode(bool enableAuto) async {
    setState(() => isTogglingAuto = true);
    try {
      String state = enableAuto ? 'ON' : 'OFF';
      await FirebaseDatabase.instance.ref('valves/auto_mode').set(state);
      setState(() => isAutoMode = enableAuto);
    } catch (e) {
    } finally {
      setState(() => isTogglingAuto = false);
    }
  }

  Future<void> _toggleValve(int id, bool turnOn) async {
    if (id == 1) {
      setState(() => isTogglingValve1 = true);
    } else {
      setState(() => isTogglingValve2 = true);
    }

    try {
      String state = turnOn ? 'OPEN' : 'CLOSED';
      await FirebaseDatabase.instance.ref('valves/valve$id').set(state);

      setState(() {
        if (id == 1) {
          isValve1Open = turnOn;
        } else {
          isValve2Open = turnOn;
        }
      });
    } catch (e) {
    } finally {
      if (id == 1) {
        setState(() => isTogglingValve1 = false);
      } else {
        setState(() => isTogglingValve2 = false);
      }
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
    // Rs. 50 per 1000 Liters (Rs. 0.05 per Liter)
    const double pricePerLiter = 0.05;
    // Restored multiplication operator (*)
    double estimatedCost = totalVolume * pricePerLiter;

    return Row(
      children: [
        Expanded(child: _metricCard('CURRENT FLOW RATE', isOnline ? '${flowMain.toStringAsFixed(1)} mL/s' : 'OFFLINE', 'Main Intake Header', const Color(0xFF00A3FF))),
        const SizedBox(width: 12),
        Expanded(child: _metricCard('ACTIVE SENSORS', isOnline ? '5 / 5' : '0 / 5', isOnline ? 'Network Linked' : 'Connection Lost', isOnline ? const Color(0xFF00E676) : const Color(0xFFFF1744))),
        const SizedBox(width: 12),
        Expanded(child: _metricCard('WATER QUALITY', isOnline ? '$tdsPPM ppm' : '---', isOnline ? turbStatus : 'Awaiting Data', (turbStatus == 'CLEAR WATER' && tdsPPM < 600) ? const Color(0xFF00E676) : const Color(0xFFFFB300))),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _metricCard('VOLUME & BILLING', isOnline ? '${totalVolume.toStringAsFixed(2)} L - Rs. ${estimatedCost.toStringAsFixed(2)}' : '---', isOnline ? 'Rate: Rs. 50.00 per 1000L' : 'Pricing Unavailable', Colors.purpleAccent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'WATER LEVEL',
            isOnline ? '${tankLevelPercent.toStringAsFixed(1)} %' : '---',
            'Main Reservoir',
            Colors.orangeAccent,
            trailing: _buildMiniTankGraphic(isOnline ? tankLevelPercent : 0.0),
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, String subtitle, Color accentColor, {Widget? trailing}) {
    Widget textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1722),
        border: Border(
          top: BorderSide(color: accentColor, width: 3),
          left: const BorderSide(color: Color(0xFF162535)),
          right: const BorderSide(color: Color(0xFF162535)),
          bottom: const BorderSide(color: Color(0xFF162535)),
        ),
      ),
      child: trailing == null
          ? textColumn
          : Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: textColumn),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }

  // Animated Mini Tank / Bottle Graphic for the Water Level Card
  Widget _buildMiniTankGraphic(double percent) {
    final double clamped = percent.clamp(0.0, 100.0);
    const double tankHeight = 52.0;
    const double tankWidth = 28.0;
    final double fillHeight = (clamped / 100.0) * (tankHeight - 3.0);

    // Dynamic liquid color: Orange-Red if low (<20%), Cyan-Blue otherwise
    final Color liquidTopColor = clamped < 20.0 ? const Color(0xFFFF5252) : const Color(0xFF00E5FF);
    final Color liquidBottomColor = clamped < 20.0 ? const Color(0xFFD50000) : const Color(0xFF0066CC);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tank / Bottle Neck Cap
        Container(
          width: 12,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF162535),
            border: Border.all(color: Colors.blueGrey.withOpacity(0.6), width: 1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(2),
              topRight: Radius.circular(2),
            ),
          ),
        ),
        // Main Tank Body
        Container(
          width: tankWidth,
          height: tankHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF070D14),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.blueGrey.withOpacity(0.6), width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3.5),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Animated Water Fill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  width: tankWidth,
                  height: fillHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        liquidTopColor.withOpacity(0.85),
                        liquidBottomColor.withOpacity(0.95),
                      ],
                    ),
                    border: fillHeight > 2.0
                        ? Border(top: BorderSide(color: Colors.white.withOpacity(0.7), width: 1.5))
                        : null,
                  ),
                ),
                // Graduation Tick Marks (75%, 50%, 25%)
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(width: 6, height: 1, color: Colors.white.withOpacity(0.35)),
                      Container(width: 9, height: 1, color: Colors.white.withOpacity(0.5)),
                      Container(width: 6, height: 1, color: Colors.white.withOpacity(0.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionAndControlNetwork() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('PIPELINE DISTRIBUTION & CONTROL NETWORK', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isAutoMode ? const Color(0xFF00E676).withOpacity(0.12) : const Color(0xFF0D1722),
                border: Border.all(color: isAutoMode ? const Color(0xFF00E676) : const Color(0xFF162535)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAutoMode ? Icons.autorenew_rounded : Icons.touch_app_rounded,
                    size: 15,
                    color: isAutoMode ? const Color(0xFF00E676) : Colors.blueGrey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isAutoMode ? 'AUTO FAILOVER: ON' : 'MODE: MANUAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isAutoMode ? const Color(0xFF00E676) : Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: isAutoMode,
                      onChanged: (!isOnline || isTogglingAuto) ? null : (val) => _toggleAutoMode(val),
                      activeColor: const Color(0xFF00E676),
                      inactiveThumbColor: Colors.blueGrey,
                      inactiveTrackColor: const Color(0xFF070D14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
            children: [
              _buildBranchCard('BRANCH A', flowA1, flowA2, isBranchALeaking),
              _buildBranchCard('BRANCH B', flowB1, flowB2, isBranchBLeaking),
              _buildValveCard(1, 'VL-01: Branch A Valve', 'Primary Line Cutoff', isValve1Open, isTogglingValve1),
              _buildValveCard(2, 'VL-02: Branch B Valve', 'Redundant Backup Cutoff', isValve2Open, isTogglingValve2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBranchCard(String branchName, double inletFlow, double outletFlow, bool isLeaking) {
    double loss = inletFlow - outletFlow;
    Color statusColor = !isOnline ? const Color(0xFFFF1744) : (isLeaking ? const Color(0xFFFF1744) : (inletFlow > 0 ? const Color(0xFF00E676) : const Color(0xFF90A4AE)));
    String bannerText = !isOnline ? 'SYSTEM OFFLINE' : (isLeaking ? '⚠ WARNING: LEAKAGE' : (inletFlow > 0 ? '✅ NORMAL FLOW' : '⏸ SYSTEM STANDBY'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1722),
        border: Border.all(color: isLeaking ? const Color(0xFFFF1744) : const Color(0xFF162535), width: isLeaking ? 2.0 : 1.0),
        boxShadow: [if (isLeaking) BoxShadow(color: const Color(0xFFFF1744).withOpacity(0.2), blurRadius: 15, spreadRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(branchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF00A3FF))),
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(isLeaking ? 'ALERT' : 'ACTIVE', style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold))
              ])
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: isOnline ? (isLeaking ? const Color(0xFFFF1744).withOpacity(0.15) : (inletFlow > 0 ? const Color(0xFF00E676).withOpacity(0.1) : const Color(0xFF162535))) : const Color(0xFF162535),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isOnline ? (isLeaking ? const Color(0xFFFF1744).withOpacity(0.5) : (inletFlow > 0 ? const Color(0xFF00E676).withOpacity(0.3) : Colors.transparent)) : Colors.transparent),
            ),
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
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isLeaking ? const Color(0xFFFF1744).withOpacity(0.1) : const Color(0xFF070D14),
              border: Border.all(color: isLeaking ? const Color(0xFFFF1744).withOpacity(0.5) : const Color(0xFF162535)),
              borderRadius: BorderRadius.circular(4),
            ),
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
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(isOnline ? (isOpen ? 'VALVE OPEN' : 'VALVE CLOSED') : 'OFFLINE', style: TextStyle(color: activeColor, fontSize: 10, fontWeight: FontWeight.bold))
              ])
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
              Text(
                isToggling ? 'TRANSMITTING...' : (isOnline ? (isAutoMode ? 'AUTO-FAILOVER ARMED' : 'READY FOR COMMAND') : 'SYSTEM UNREACHABLE'),
                style: TextStyle(fontSize: 9, color: isToggling ? const Color(0xFF00A3FF) : (isAutoMode ? const Color(0xFF00E676) : Colors.blueGrey)),
              ),
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
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            const SizedBox(width: 4),
            const Text('mL/s', style: TextStyle(fontSize: 10, color: Colors.grey))
          ],
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
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFF1744).withOpacity(0.15), border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.5)), borderRadius: BorderRadius.circular(4)),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF1744), size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('CONSUMPTION ANOMALY: Leak detected in ${leakingBranches.join(" & ")}. Graph data may be skewed by unaccounted volume loss.', style: const TextStyle(color: Color(0xFFFF1744), fontSize: 10, fontWeight: FontWeight.bold)))
              ]),
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFF162535), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text('Time (Minutes)', style: TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    axisNameSize: 22,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('${value.toInt()}m', style: const TextStyle(color: Colors.blueGrey, fontSize: 11)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(bottom: 8.0),
                      child: Text('Flow (mL/s)', style: TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    axisNameSize: 22,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.blueGrey, fontSize: 11));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    bottom: BorderSide(color: Color(0xFF162535), width: 1),
                    left: BorderSide(color: Color(0xFF162535), width: 1),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: consumptionSpots,
                    isCurved: true,
                    preventCurveOverShooting: true, // Prevents curve from dipping below 0.0
                    color: hasAnyLeak ? const Color(0xFFFF1744) : const Color(0xFF00A3FF),
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: (hasAnyLeak ? const Color(0xFFFF1744) : const Color(0xFF00A3FF)).withOpacity(0.1)),
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
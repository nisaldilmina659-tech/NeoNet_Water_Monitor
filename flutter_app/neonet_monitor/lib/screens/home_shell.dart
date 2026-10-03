import 'package:flutter/material.dart';
import '../views/dashboard_view.dart';
import '../views/alerts_view.dart';
import '../views/sensors_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  // 1. Updated the views list to only contain the 3 active screens
  final List<Widget> _views = [
    const DashboardView(),
    const SensorsView(),
    const AlertsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Navigation Sidebar Left Panel
          Container(
            width: 240,
            decoration: const BoxDecoration(
              color: Color(0xFF09111A),
              border: Border(right: BorderSide(color: Color(0xFF162535))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSidebarHeader(),
                const Divider(),
                const SizedBox(height: 16),

                // 2. Updated Nav Buttons (ALERTS is now index 2)
                _buildNavButton('DASHBOARD', 0),
                _buildNavButton('SENSORS', 1),
                _buildNavButton('ALERTS', 2),

                const Spacer(),
                _buildSystemStatusFooter(),
              ],
            ),
          ),
          // Core Screen Display Workspace Content
          Expanded(
            child: Column(
              children: [
                _buildTopToolbarHeader(),
                Expanded(child: _views[_selectedIndex]),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return const Padding(
      padding: EdgeInsets.all(24.0),
      child: Row(
        children: [
          Icon(Icons.hexagon, color: Color(0xFF00A3FF), size: 28),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NEONET', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
              Text('WATER MONITOR v2.4', style: TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildNavButton(String title, int index) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          border: isSelected ? const Border(left: BorderSide(color: Color(0xFF00A3FF), width: 4)) : null,
          color: isSelected ? const Color(0xFF0D1722) : Colors.transparent,
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00A3FF) : const Color(0xFFABC2D6),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildSystemStatusFooter() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SYSTEM STATUS', style: TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 12),
          _statusRow('API', 'OK', const Color(0xFF00E676)),
          _statusRow('DB', 'OK', const Color(0xFF00E676)),
          _statusRow('INGEST', 'OK', const Color(0xFF00E676)),
          _statusRow('ALERTS', 'WARN', const Color(0xFFFFB300)),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      key: ValueKey(label),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8BA3B7))),
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTopToolbarHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF162535))),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
            ],
          ),
          const Spacer(),
          const Text('NETWORK UTC ', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const Text('JUL 17, 2026 08:53:59', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const VerticalDivider(indent: 20, endIndent: 20, width: 32),
          const Text('OPERATOR: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const Text('SYS_ADMIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
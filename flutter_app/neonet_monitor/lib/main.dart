import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const NeoNetApp());
}

class NeoNetApp extends StatelessWidget {
  const NeoNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeoNet Water Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070D14),
        cardColor: const Color(0xFF0D1722),
        dividerColor: const Color(0xFF162535),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00A3FF),
          secondary: Color(0xFF00E676),
          error: Color(0xFFFF1744),
          surface: Color(0xFF0D1722),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            color: Color(0xFFABC2D6),
            fontFamily: 'monospace',
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF8BA3B7),
            fontFamily: 'monospace',
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
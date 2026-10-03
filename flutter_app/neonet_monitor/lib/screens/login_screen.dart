import 'package:flutter/material.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controllers to read the text input
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Variable to hold the error message if login fails
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    // Check if the credentials match our secure operator account
    if (_emailController.text.trim() == 'NEONET' && _passwordController.text == 'admin123') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
    } else {
      // Trigger a UI update to show the error
      setState(() {
        _errorMessage = 'ACCESS DENIED: Invalid email or password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF0A1B2C), Color(0xFF070D14)],
            radius: 1.2,
          ),
        ),
        child: Center(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border.all(color: const Color(0xFF00A3FF).withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00A3FF).withOpacity(0.05),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hexagon, size: 48, color: Color(0xFF00A3FF)),
                const SizedBox(height: 16),
                const Text(
                  'OPERATOR ACCESS',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                const Text('SECURE AUTHENTICATION REQUIRED', style: TextStyle(fontSize: 10, color: Colors.grey)),

                const SizedBox(height: 32),
                _buildTextField('EMAIL ADDRESS', 'NEONET', false, _emailController),
                const SizedBox(height: 16),
                _buildTextField('PASSWORD', 'admin123', true, _passwordController),

                // Dynamically show the error message if it exists
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF1744).withOpacity(0.15),
                      border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF1744), size: 16),
                        const SizedBox(width: 8),
                        Text(_errorMessage!, style: const TextStyle(color: Color(0xFFFF1744), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF052137),
                    foregroundColor: const Color(0xFF00A3FF),
                    minimumSize: const Size(double.infinity, 50),
                    side: const BorderSide(color: Color(0xFF00A3FF)),
                    shape: const RoundedRectangleBorder(),
                  ),
                  onPressed: _handleLogin,
                  child: const Text('LOGIN', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Updated to accept the specific controller for each field
  Widget _buildTextField(String label, String hint, bool isObscure, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isObscure,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFF09111A),
            enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF162535))),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00A3FF))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text.trim();
      if (username.isEmpty || password.isEmpty) {
        setState(() {
          _error = 'Please enter username and password';
          _loading = false;
        });
        return;
      }

      if (_isLogin) {
        final data = await login(username, password);
        await _saveSession(data);
      } else {
        final data = await register(username, password);
        await _saveSession(data);
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = _extractError(e.toString());
        _loading = false;
      });
    }
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final p = await SharedPreferences.getInstance();
    final userId = (data['user_id'] as num?)?.toInt();
    if (userId != null) {
      await p.setInt('checkmath_user_id', userId);
    }
    await p.setString('checkmath_username', _usernameCtrl.text.trim());
  }

  String _extractError(String err) {
    if (err.contains('Username already taken')) return 'Username already taken';
    if (err.contains('Invalid username or password')) return 'Invalid username or password';
    if (err.contains('detail')) {
      final start = err.indexOf('"detail":"');
      if (start != -1) {
        final sub = err.substring(start + 10);
        final end = sub.indexOf('"');
        if (end != -1) return sub.substring(0, end);
      }
    }
    return 'Something went wrong. Try again.';
  }

  Future<void> _skipAuth() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('checkmath_user_id');
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF302E2B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF262421),
        foregroundColor: const Color(0xFFD4D4D4),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF888888)),
            tooltip: 'Server Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLogo(),
                const SizedBox(height: 24),
                Text(
                  _isLogin ? 'Welcome Back' : 'Create Account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFD4D4D4),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin
                      ? 'Sign in to save your progress'
                      : 'Sign up to start your journey',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
                ),
                const SizedBox(height: 32),
                _field(
                  label: 'Username',
                  icon: Icons.person,
                  controller: _usernameCtrl,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                _field(
                  label: 'Password',
                  icon: Icons.lock,
                  controller: _passwordCtrl,
                  obscure: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFD4574B), fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF739552),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 4,
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isLogin ? 'Sign In' : 'Sign Up',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Sign Up"
                        : 'Already have an account? Sign In',
                    style: const TextStyle(color: Color(0xFF888888)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : _skipAuth,
                  child: const Text(
                    'Play as Guest',
                    style: TextStyle(color: Color(0xFF555555)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF739552),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Text(
          '✦',
          style: TextStyle(fontSize: 36, color: Colors.white),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool obscure = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Color(0xFFD4D4D4)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF888888)),
        prefixIcon: Icon(icon, color: const Color(0xFF888888)),
        filled: true,
        fillColor: const Color(0xFF262421),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3E3B37)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3E3B37)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF739552), width: 2),
        ),
      ),
    );
  }
}

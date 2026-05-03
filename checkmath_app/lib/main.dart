import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'services/api_service.dart';
import 'services/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Warm-up SharedPreferences so subsequent reads are instant (no cold-start lag)
  await initPrefsCache();
  await AudioService().init();
  AudioService().ensureBgmPlaying();
  runApp(const CheckMathApp());
}

class CheckMathApp extends StatelessWidget {
  const CheckMathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheckMath',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF302E2B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF739552),
          secondary: Color(0xFFEBECD0),
          surface: Color(0xFF262421),
          onSurface: Color(0xFFD4D4D4),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF262421),
          foregroundColor: Color(0xFFD4D4D4),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF739552)),
        useMaterial3: true,
      ),
      home: const AuthScreen(),
    );
  }
}

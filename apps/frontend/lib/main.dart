import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ThesisGateApp());
}

class ThesisGateApp extends StatelessWidget {
  const ThesisGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThesisGate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2188FF),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
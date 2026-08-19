import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/lock/lock_gate.dart';
import 'home_shell.dart';

void main() {
  runApp(const ProviderScope(child: ForkApp()));
}

class ForkApp extends StatelessWidget {
  const ForkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fork',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        useMaterial3: true,
        // Material 3's default light surface off deepOrange is still
        // near-white - same fix as Spine got: a warm-tinted background
        // and an AppBar in the icon's actual orange, instead of leaving
        // it to the seed's washed-out auto-derived surface.
        scaffoldBackgroundColor: const Color(0xFFFCEBE3),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFE64A19), foregroundColor: Colors.white),
      ),
      // Dark mode left to Material 3's auto-derived palette from the same
      // seed - no hand-picked overrides here, unlike the light theme.
      darkTheme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true, brightness: Brightness.dark),
      home: const LockGate(child: HomeShell()),
    );
  }
}

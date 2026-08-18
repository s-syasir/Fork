import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

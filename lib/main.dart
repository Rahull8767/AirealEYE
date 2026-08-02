import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/config/app_config.dart';
import 'package:aerial_eye/screens/splash_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: AerialEyeApp(),
    ),
  );
}

class AerialEyeApp extends ConsumerWidget {
  const AerialEyeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}

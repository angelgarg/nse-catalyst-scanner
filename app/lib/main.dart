import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/alerts.dart';
import 'state/providers.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  try {
    await Alerts.init();
  } catch (_) {
    // Alerts are optional; never block app start on them.
  }
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const SpikewiseApp(),
  ));
}

class SpikewiseApp extends ConsumerWidget {
  const SpikewiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.read(boolPrefProvider(kOnboardedKey));
    return MaterialApp(
      title: 'Spikewise',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: onboarded ? const HomeShell() : const OnboardingScreen(),
    );
  }
}

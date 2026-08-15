import 'package:flutter/material.dart';
import 'package:tri_flash/app/app.dart';
import 'package:tri_flash/state/app_preferences.dart';

/// Entry point of the application.
///
/// Keeping this file tiny makes it obvious that the app simply boots the
/// [TriFlashApp] widget defined in `lib/app/app.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  runApp(const TriFlashApp());
}

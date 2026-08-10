import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/screens/main/main_screen.dart';
import 'package:tri_flash/state/app_preferences.dart';

/// Root widget for the Tri Flash application.
///
/// Keeping the [MaterialApp] definition in its own file makes it easier to
/// locate global configuration (theme, routes, etc.) and keeps `main.dart`
/// focused on bootstrapping the app.
class TriFlashApp extends StatelessWidget {
  const TriFlashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPreferences.instance,
      builder:
          (context, _) => MaterialApp(
            title: 'Tri Flash',
            debugShowCheckedModeBanner: false,
            locale: AppPreferences.instance.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              primarySwatch: Colors.blue,
              visualDensity: VisualDensity.adaptivePlatformDensity,
            ),
            home: const MainScreen(),
          ),
    );
  }
}

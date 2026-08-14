import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'services/app_language.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await AppLanguage.load();

  runApp(const DriveEasyApp());
}

class DriveEasyApp extends StatefulWidget {
  const DriveEasyApp({super.key});

  @override
  State<DriveEasyApp> createState() => _DriveEasyAppState();
}

class _DriveEasyAppState extends State<DriveEasyApp> {
  @override
  void initState() {
    super.initState();
    AppLanguage.code.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    AppLanguage.code.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DriveEasy',
      theme: AppTheme.lightTheme,
      locale: AppLanguage.currentLocale,
      supportedLocales: AppLanguage.locales.values,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}

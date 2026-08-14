import 'package:flutter/material.dart';

import 'login_screen.dart';

/// Branded launch screen: shows the DriveEasy splash artwork for a couple of
/// seconds right after the Flutter engine starts, then hands off to the
/// login flow.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0057D8),
      body: SizedBox.expand(
        child: Image.asset(
          "assets/images/splash.png",
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

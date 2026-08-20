import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import 'home/home_screen.dart';
import 'teacher_dashborad.dart';
import 'super_admin_screen.dart';
import '../services/support_contact.dart';

/// Branded launch screen: shows the DriveEasy splash artwork for a couple of
/// seconds right after the Flutter engine starts, then decides where to go.
///
/// If a user is already signed in (Firebase keeps the session on the device
/// automatically), we skip the login screen entirely and jump straight to
/// their dashboard. Otherwise we fall back to the login screen as before.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _decideNextScreen);
  }

  Future<void> _decideNextScreen() async {
    final user = FirebaseAuth.instance.currentUser;

    // No saved session -> normal login flow.
    if (user == null) {
      _goTo(const LoginScreen());
      return;
    }

    try {
      // Make sure the account still exists / token is valid.
      await user.reload();
    } catch (_) {
      // Token revoked, user deleted, etc. -> sign out and show login.
      await FirebaseAuth.instance.signOut();
      _goTo(const LoginScreen());
      return;
    }

    if (!mounted) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        _goTo(const LoginScreen());
        return;
      }

      final data = userDoc.data() as Map<String, dynamic>;
      final String role = data["role"] ?? "";

      if (data["isDeleted"] == true) {
        final purgeAtTs = data["purgeAt"] as Timestamp?;
        final deletedAtTs = data["deletedAt"] as Timestamp?;

        if (purgeAtTs != null && purgeAtTs.toDate().isAfter(DateTime.now())) {
          if (!mounted) return;
          final restored = await showAccountRestoreDialog(
            context: context,
            uid: user.uid,
            deletedAt: deletedAtTs?.toDate() ?? DateTime.now(),
            purgeAt: purgeAtTs.toDate(),
          );

          if (!restored) {
            await FirebaseAuth.instance.signOut();
            _goTo(const LoginScreen());
            return;
          }
          // Restored — fall through to normal role routing below.
        } else {
          await FirebaseAuth.instance.signOut();
          _goTo(const LoginScreen());
          return;
        }
      }

      // Same email-verification rule used on manual login.
      if (role != "super_admin" && !user.emailVerified) {
        await FirebaseAuth.instance.signOut();
        _goTo(const LoginScreen());
        return;
      }

      if (role == "super_admin" || role == "admin") {
        _goTo(const SuperAdminScreen());
      } else if (role == "student") {
        _goTo(const HomeScreen());
      } else if (role == "teacher") {
        final bool isVerified = data["isVerified"] ?? false;
        final bool isBlocked = data["isBlocked"] ?? false;

        if (isBlocked || !isVerified) {
          await FirebaseAuth.instance.signOut();
          _goTo(const LoginScreen());
          return;
        }
        _goTo(const TeacherDashboard());
      } else {
        // Unknown role -> safest fallback.
        await FirebaseAuth.instance.signOut();
        _goTo(const LoginScreen());
      }
    } catch (_) {
      // Any unexpected error (e.g. no network) -> don't trap the user,
      // send them to login where they can retry.
      _goTo(const LoginScreen());
    }
  }

  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
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

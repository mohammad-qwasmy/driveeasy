import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'phone_verification_screen.dart';
import 'login_screen.dart';
import '../services/app_helpers.dart';

/// Real email ownership check using Firebase Auth's own verification link.
/// The Auth account technically exists as soon as it's created, but it
/// stays non-functional until this screen detects the link was clicked:
/// only then do we flip `emailVerified` on the user doc (and on the
/// teacher_requests doc, so admins never see an unverified teacher's
/// request) and let the person continue into the app.
class EmailVerificationScreen extends StatefulWidget {
  final String role;
  final String phone;

  const EmailVerificationScreen({
    super.key,
    required this.role,
    required this.phone,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool isChecking = false;
  bool isSending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _checkVerified(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _markVerified(String uid) async {
    await syncTeacherRequestEmailVerified(uid);
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (!silent) setState(() => isChecking = true);

    final user = FirebaseAuth.instance.currentUser;
    await user?.reload();
    final refreshed = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (refreshed != null && refreshed.emailVerified) {
      _timer?.cancel();
      await _markVerified(refreshed.uid);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PhoneVerificationScreen(role: widget.role, phone: widget.phone),
        ),
      );
      return;
    }

    if (!silent) {
      setState(() => isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("لم يتم تفعيل البريد الإلكتروني بعد")),
      );
    }
  }

  Future<void> _resend() async {
    setState(() => isSending = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم إرسال رابط التفعيل مجدداً")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر الإرسال: $e")),
      );
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? "";

    return Scaffold(
      appBar: AppBar(title: const Text("تفعيل البريد الإلكتروني")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mark_email_unread_rounded, size: 80, color: Color(0xff1565C0)),
            const SizedBox(height: 20),
            Text(
              "أرسلنا رابط تفعيل إلى:\n$email",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "افتح الرابط من بريدك الإلكتروني الحقيقي (تأكد أنك تفقّد مجلد Spam)، ثم عد إلى هذه الشاشة. لن يصبح حسابك فعّالاً قبل ذلك.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isChecking ? null : () => _checkVerified(),
                child: isChecking
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("لقد قمت بالتفعيل"),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: isSending ? null : _resend,
              child: const Text("إعادة إرسال الرابط"),
            ),
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text("تسجيل الخروج", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}

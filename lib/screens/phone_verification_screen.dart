import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'school_selection_screen.dart';
import 'login_screen.dart';

/// Verifies phone ownership via a real Firebase Phone Auth SMS code and
/// links it to the current account. Requires the Phone provider to be
/// enabled in the Firebase console (with SHA-1/SHA-256 for Android, or
/// APNs for iOS) — if it isn't configured yet, verification will fail with
/// a clear error and the user can skip for now and verify later from their
/// profile.
class PhoneVerificationScreen extends StatefulWidget {
  final String role;
  final String phone;

  const PhoneVerificationScreen({
    super.key,
    required this.role,
    required this.phone,
  });

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final TextEditingController codeController = TextEditingController();
  String? verificationId;
  bool isSendingCode = false;
  bool isVerifying = false;
  bool codeSent = false;

  Future<void> _sendCode() async {
    setState(() => isSendingCode = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _linkCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("تعذر إرسال رمز التحقق: ${e.message}")),
          );
          setState(() => isSendingCode = false);
        },
        codeSent: (String verId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            verificationId = verId;
            codeSent = true;
            isSendingCode = false;
          });
        },
        codeAutoRetrievalTimeout: (String verId) {
          verificationId = verId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isSendingCode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر إرسال رمز التحقق: $e")),
      );
    }
  }

  Future<void> _verifyCode() async {
    if (verificationId == null || codeController.text.trim().isEmpty) return;

    setState(() => isVerifying = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId!,
        smsCode: codeController.text.trim(),
      );
      await _linkCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("رمز غير صحيح: ${e.message}")),
      );
      setState(() => isVerifying = false);
    }
  }

  Future<void> _linkCredential(PhoneAuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      // already linked or in-use — treat as success either way once
      // verificationCompleted/verifyCode gave us a valid credential.
      if (e.code != "credential-already-in-use" &&
          e.code != "provider-already-linked") {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("تعذر ربط رقم الهاتف: ${e.message}")),
        );
        setState(() => isVerifying = false);
        return;
      }
    }

    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .update({"phoneVerified": true});

    if (!mounted) return;
    _continue();
  }

  Future<void> _skip() async {
    _continue();
  }

  Future<void> _continue() async {
    if (widget.role == "student") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SchoolSelectionScreen()),
      );
    } else {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "تم إرسال طلبك للإدارة، سيتم تفعيل الحساب بعد الموافقة.",
          ),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تفعيل رقم الهاتف")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sms_rounded, size: 80, color: Color(0xff1565C0)),
            const SizedBox(height: 20),
            Text(
              codeSent
                  ? "أدخل الرمز المرسل إلى ${widget.phone}"
                  : "سيتم إرسال رمز تحقق عبر رسالة نصية إلى:\n${widget.phone}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (codeSent)
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, letterSpacing: 6),
                decoration: const InputDecoration(
                  labelText: "رمز التحقق",
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isSendingCode || isVerifying
                    ? null
                    : (codeSent ? _verifyCode : _sendCode),
                child: (isSendingCode || isVerifying)
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(codeSent ? "تأكيد الرمز" : "إرسال رمز التحقق"),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _skip,
              child: const Text("تخطي الآن وتفعيل لاحقاً من حسابي"),
            ),
          ],
        ),
      ),
    );
  }
}

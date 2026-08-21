import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'register_screen.dart';
import 'home/home_screen.dart';
import 'teacher_dashborad.dart';
import 'super_admin_screen.dart';
import '../services/app_language.dart';
import '../services/app_helpers.dart';
import '../services/support_contact.dart';
import 'email_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool hidePassword = true;

  @override
  void initState() {
    super.initState();
    // Belt-and-suspenders: strip any whitespace the instant it appears in
    // the email field, whatever put it there (keyboard suggestion, bidi
    // mark, paste, autofill...). Preserves cursor position so typing still
    // feels normal.
    emailController.addListener(_stripSpacesFromEmail);
  }

  void _stripSpacesFromEmail() {
    final text = emailController.text;
    if (!text.contains(" ") && !text.contains("\u200E") && !text.contains("\u200F")) {
      return;
    }
    final cleaned = text.replaceAll(RegExp(r'[\s\u200E\u200F]'), "");
    final newOffset = (emailController.selection.baseOffset - (text.length - cleaned.length))
        .clamp(0, cleaned.length);
    emailController.value = TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }

  @override
  void dispose() {
    emailController.removeListener(_stripSpacesFromEmail);
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _forgotPassword() async {
    if (emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("أدخل بريدك الإلكتروني أولاً ثم اضغط مجدداً")),
      );
      return;
    }

    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: emailController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم إرسال رابط استعادة كلمة المرور إلى بريدك")),
      );
    } on FirebaseAuthException catch (e) {
      String message = "تعذر إرسال رابط الاستعادة";
      if (e.code == "user-not-found") {
        message = "لا يوجد حساب بهذا البريد الإلكتروني";
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> loginUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      setState(() => isLoading = true);

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists) {
        // The Auth account exists but its Firestore profile is gone —
        // can't safely route anywhere. Sign out instead of crashing.
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تعذر العثور على بيانات هذا الحساب.")),
        );
        return;
      }

      // Read everything through this one safe map from here on — never
      // through userDoc["field"] directly, since that throws if a field
      // is missing entirely (not just null), which would otherwise crash
      // every single login the moment any one field is absent from an
      // older or edge-case account.
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      String role = userData["role"] ?? "";

      // Sync the teacher_requests doc's emailVerified flag right here too
      // (not just on the dedicated verification screen) — covers the case
      // where a teacher verified their email after closing the app, then
      // came straight back to log in instead of revisiting that screen.
      if (role == "teacher" && userCredential.user!.emailVerified) {
        await syncTeacherRequestEmailVerified(userCredential.user!.uid);
      }

      if (userData["isDeleted"] == true) {
        final purgeAtTs = userData["purgeAt"] as Timestamp?;
        final deletedAtTs = userData["deletedAt"] as Timestamp?;

        if (purgeAtTs != null && purgeAtTs.toDate().isAfter(DateTime.now())) {
          if (!mounted) return;
          final restored = await showAccountRestoreDialog(
            context: context,
            uid: userCredential.user!.uid,
            deletedAt: deletedAtTs?.toDate() ?? DateTime.now(),
            purgeAt: purgeAtTs.toDate(),
          );

          if (!restored) {
            await FirebaseAuth.instance.signOut();
            if (mounted) setState(() => isLoading = false);
            return;
          }
          // Restored successfully — fall through to normal role routing below.
        } else {
          // Recovery window has passed.
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("هذا الحساب لم يعد متاحاً.")),
          );
          return;
        }
      }

      if (!mounted) return;

      // Email must be verified before the account can be used, for both
      // students and teachers.
      if (role != "super_admin" && !userCredential.user!.emailVerified) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => EmailVerificationScreen(
              role: role,
              phone: userData["phone"] ?? "",
            ),
          ),
        );
        return;
      }

      if (role == "super_admin") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SuperAdminScreen()),
        );
      } else if (role == "admin") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SuperAdminScreen()),
        );
      } else if (role == "student") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else if (role == "teacher") {
        bool isVerified = userData["isVerified"] ?? false;
        bool isBlocked = userData["isBlocked"] ?? false;

        if (isBlocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("تم تعطيل حسابك، يرجى التواصل مع الإدارة."),
            ),
          );
          await FirebaseAuth.instance.signOut();
          return;
        }

        if (!isVerified) {
          // Distinguish "still waiting" from "was actually rejected" —
          // otherwise a rejected teacher sees the same "under review"
          // message forever and never finds out their request was denied.
          String message = "طلب تسجيلك قيد مراجعة الإدارة";
          try {
            final requestSnap = await FirebaseFirestore.instance
                .collection("teacher_requests")
                .where("teacherId", isEqualTo: userCredential.user!.uid)
                .limit(1)
                .get();
            if (requestSnap.docs.isNotEmpty &&
                requestSnap.docs.first.data()["status"] == "rejected") {
              message = "تم رفض طلب تسجيلك كمدرب. يرجى التواصل مع الإدارة لمزيد من المعلومات.";
            }
          } catch (_) {
            // If this lookup fails for any reason, fall back to the
            // generic "under review" message rather than blocking login.
          }

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          await FirebaseAuth.instance.signOut();
          return;
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const TeacherDashboard()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = "حدث خطأ";

      if (e.code == "user-not-found") {
        message = "الحساب غير موجود";
      } else if (e.code == "wrong-password") {
        message = "كلمة المرور غير صحيحة";
      } else if (e.code == "invalid-email") {
        message = "البريد الإلكتروني غير صالح";
      } else if (e.code == "invalid-credential") {
        message = "البريد الإلكتروني أو كلمة المرور غير صحيحة";
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F9FF),
      appBar: AppBar(
        backgroundColor: Colors.blue,
        centerTitle: true,
        elevation: 0,
        title: Text(tr("app_name"), style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.directions_car, size: 90, color: Colors.blue),
                  const SizedBox(height: 15),
                  Center(
                    child: Text(
                      tr("welcome_back"),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 35),
                  // Forced LTR: email/password are always Latin-script
                  // content even when the app's overall layout is RTL
                  // (Arabic). Leaving them under the ambient RTL
                  // Directionality can make iOS insert an invisible
                  // bidi direction-mark character as you type — which
                  // looks like nothing on screen but breaks validation
                  // until manually deleted. Forcing LTR here removes
                  // that entirely for these two fields specifically.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textCapitalization: TextCapitalization.none,
                      textAlign: TextAlign.left,
                      // Disables iOS's QuickType suggestion bar for this field.
                      // That bar is what silently inserts a trailing space
                      // when a suggested word/email is tapped or auto-applied
                      // while typing — turning it off removes the one
                      // remaining source of stray spaces, without touching
                      // autofillHints (already removed) or autocorrect.
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: tr("email"),
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "أدخل البريد الإلكتروني";
                        }
                        if (!value.trim().contains("@")) {
                          return "البريد الإلكتروني غير صحيح";
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextFormField(
                      controller: passwordController,
                      obscureText: hidePassword,
                      textAlign: TextAlign.left,
                      decoration: InputDecoration(
                        labelText: tr("password"),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => hidePassword = !hidePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "أدخل كلمة المرور";
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: Text(tr("forgot_password")),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : loginUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              tr("login"),
                              style: const TextStyle(color: Colors.white, fontSize: 18),
                            ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: Text(tr("create_account")),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

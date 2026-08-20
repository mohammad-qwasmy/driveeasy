import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'register_screen.dart';
import 'home/home_screen.dart';
import 'teacher_dashborad.dart';
import 'super_admin_screen.dart';
import '../services/app_language.dart';
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
  bool rememberMe = false;

  static const _rememberedEmailKey = "remembered_email";

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_rememberedEmailKey);
    if (savedEmail != null && savedEmail.isNotEmpty) {
      if (!mounted) return;
      // Guard against a race: if the user already started typing before
      // this async load resolved, never overwrite what they typed.
      if (emailController.text.isNotEmpty) return;
      setState(() {
        emailController.text = savedEmail;
        rememberMe = true;
      });
    }
  }

  Future<void> _persistRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString(_rememberedEmailKey, emailController.text.trim());
    } else {
      await prefs.remove(_rememberedEmailKey);
    }
  }

  @override
  void dispose() {
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

      String role = userDoc["role"];

      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
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

      await _persistRememberMe();

      if (!mounted) return;

      // Email must be verified before the account can be used, for both
      // students and teachers.
      if (role != "super_admin" && !userCredential.user!.emailVerified) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => EmailVerificationScreen(
              role: role,
              phone: (userDoc.data() as Map<String, dynamic>?)?["phone"] ?? "",
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
        bool isVerified = userDoc["isVerified"] ?? false;
        bool isBlocked = userDoc["isBlocked"] ?? false;

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("طلب تسجيلك قيد مراجعة الإدارة")),
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
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textCapitalization: TextCapitalization.none,
                    autofillHints: const [AutofillHints.email],
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
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: passwordController,
                    obscureText: hidePassword,
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
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: rememberMe,
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr("remember_me")),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) => setState(() => rememberMe = value!),
                  ),
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

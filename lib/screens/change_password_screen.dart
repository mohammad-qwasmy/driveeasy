import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Changes the account password for real via Firebase Auth: re-authenticates
/// with the current password first (required by Firebase before a sensitive
/// update), then applies the new one.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  bool isSaving = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (newController.text != confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("كلمتا المرور الجديدتان غير متطابقتين")),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentController.text.trim(),
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newController.text.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم تغيير كلمة المرور بنجاح")),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String message = "حدث خطأ";
      if (e.code == "wrong-password" || e.code == "invalid-credential") {
        message = "كلمة المرور الحالية غير صحيحة";
      } else if (e.code == "weak-password") {
        message = "كلمة المرور الجديدة ضعيفة جداً";
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تغيير كلمة المرور")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: currentController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "كلمة المرور الحالية",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? "أدخل كلمة المرور الحالية" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "كلمة المرور الجديدة",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return "أدخل كلمة المرور الجديدة";
                  if (v.length < 6) return "يجب أن تكون 6 أحرف على الأقل";
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "تأكيد كلمة المرور الجديدة",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? "أكد كلمة المرور" : null,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isSaving ? null : _submit,
                  child: isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("حفظ كلمة المرور الجديدة"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

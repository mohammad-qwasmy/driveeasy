import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../firebase_options.dart';

/// Lets a super admin create brand-new "admin" / "super_admin" accounts
/// directly from the app (no need to touch the Firebase console), and
/// review / remove the existing ones.
class SuperAdminsScreen extends StatefulWidget {
  const SuperAdminsScreen({super.key});

  @override
  State<SuperAdminsScreen> createState() => _SuperAdminsScreenState();
}

class _SuperAdminsScreenState extends State<SuperAdminsScreen> {
  Future<void> _openCreateAdminSheet() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = "admin";
    bool isSaving = false;
    bool hidePassword = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "إضافة حساب أدمن جديد",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "الاسم",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? "أدخل الاسم" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "البريد الإلكتروني",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return "أدخل البريد الإلكتروني";
                        if (!v.contains("@")) return "بريد إلكتروني غير صالح";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passwordController,
                      obscureText: hidePassword,
                      decoration: InputDecoration(
                        labelText: "كلمة المرور",
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setSheetState(() => hidePassword = !hidePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 6) return "٦ أحرف على الأقل";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text("نوع الحساب", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("أدمن"),
                            selected: selectedRole == "admin",
                            onSelected: (_) => setSheetState(() => selectedRole = "admin"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("سوبر أدمن"),
                            selected: selectedRole == "super_admin",
                            onSelected: (_) => setSheetState(() => selectedRole = "super_admin"),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;

                                setSheetState(() => isSaving = true);

                                final error = await _createAdminAccount(
                                  name: nameController.text.trim(),
                                  email: emailController.text.trim(),
                                  password: passwordController.text,
                                  role: selectedRole,
                                );

                                setSheetState(() => isSaving = false);

                                if (!sheetContext.mounted) return;

                                if (error == null) {
                                  Navigator.pop(sheetContext);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("تم إنشاء الحساب بنجاح")),
                                    );
                                  }
                                } else {
                                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                                    SnackBar(content: Text(error)),
                                  );
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text("إنشاء الحساب", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Creates the Firebase Auth account + the Firestore user doc without
  /// disturbing the currently signed-in super admin's session. It does this
  /// by spinning up a temporary, throwaway secondary [FirebaseApp] just for
  /// the sign-up call, then tearing it down right after.
  Future<String?> _createAdminAccount({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: "adminCreation-${DateTime.now().millisecondsSinceEpoch}",
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      final credential = await tempAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await FirebaseFirestore.instance.collection("users").doc(credential.user!.uid).set({
        "name": name,
        "email": email,
        "role": role,
        "createdAt": Timestamp.now(),
      });

      await tempAuth.signOut();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == "email-already-in-use") {
        return "هذا البريد الإلكتروني مستخدم مسبقًا";
      }
      if (e.code == "weak-password") {
        return "كلمة المرور ضعيفة جدًا";
      }
      return "تعذر إنشاء الحساب: ${e.message}";
    } catch (e) {
      return "حدث خطأ غير متوقع";
    } finally {
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  Future<void> _deleteAdmin(BuildContext context, String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف الحساب"),
        content: Text(
          "هل تريد حذف حساب \"$name\"؟ سيفقد صلاحية الدخول للوحة الأدمن فورًا.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection("users").doc(uid).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("إدارة حسابات الأدمن"),
        backgroundColor: Colors.red,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.red,
        onPressed: _openCreateAdminSheet,
        icon: const Icon(Icons.person_add),
        label: const Text("إضافة أدمن"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .where("role", whereIn: ["admin", "super_admin"])
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final admins = snapshot.data!.docs;

          if (admins.isEmpty) {
            return const Center(child: Text("لا يوجد حسابات أدمن بعد"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: admins.length,
            itemBuilder: (context, index) {
              final doc = admins[index];
              final data = doc.data() as Map<String, dynamic>;
              final isSuper = data["role"] == "super_admin";

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSuper ? Colors.red : Colors.indigo,
                    child: const Icon(Icons.admin_panel_settings, color: Colors.white),
                  ),
                  title: Text(data["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    "${data["email"] ?? ""}\n${isSuper ? "سوبر أدمن" : "أدمن"}",
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteAdmin(context, doc.id, data["name"] ?? ""),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

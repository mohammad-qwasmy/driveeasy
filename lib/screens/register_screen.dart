import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'email_verification_screen.dart';
import '../services/app_language.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool hidePassword = true;
  bool hideConfirmPassword = true;

  String selectedRole = "student";
  String? teacherLicenseType;
  String? teacherSchoolId;
  String? teacherSchoolName;

  @override
  void initState() {
    super.initState();
    // Same safety net as the login screen: strip any whitespace or hidden
    // bidi direction marks the instant they appear in the email field.
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
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> registerUser() async {
    if (!_formKey.currentState!.validate()) return;

    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("كلمتا المرور غير متطابقتين"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (selectedRole == "teacher" && teacherLicenseType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اختر نوع الرخصة التي ستقوم بتدريسها")),
      );
      return;
    }

    if (selectedRole == "teacher" && teacherSchoolId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اختر المدرسة التي تنتمي إليها")),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await FirebaseFirestore.instance.collection("users").doc(userCredential.user!.uid).set({
        "uid": userCredential.user!.uid,
        "name": nameController.text.trim(),
        "email": emailController.text.trim(),
        "phone": phoneController.text.trim(),
        "role": selectedRole,
        "profileImage": "",
        "licenseType": selectedRole == "teacher" ? teacherLicenseType : "",
        "schoolId": selectedRole == "teacher" ? teacherSchoolId : "",
        "schoolName": selectedRole == "teacher" ? teacherSchoolName : "",
        "teacherId": "",
        "rating": 0.0,
        "ratingCount": 0,
        "lessons": 0,
        "bookings": 0,
        "city": "",
        "requiredLessons": 0,
        "isVerified": false,
        "isBlocked": false,
        "phoneVerified": false,
        "emailVerified": false,
        "createdAt": Timestamp.now(),
      });

      if (selectedRole == "teacher") {
        await FirebaseFirestore.instance.collection("teacher_requests").add({
          "teacherId": userCredential.user!.uid,
          "teacherName": nameController.text.trim(),
          "email": emailController.text.trim(),
          "phone": phoneController.text.trim(),
          "licenseType": teacherLicenseType,
          "schoolId": teacherSchoolId,
          "schoolName": teacherSchoolName,
          "emailVerified": false,
          "status": "pending",
          "createdAt": Timestamp.now(),
        });
      }

      // Real email verification link, sent by Firebase Auth. The account
      // stays non-functional (and hidden from the admin's teacher list)
      // until this link is clicked.
      await userCredential.user!.sendEmailVerification();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => EmailVerificationScreen(
            role: selectedRole,
            phone: phoneController.text.trim(),
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = "حدث خطأ";
      if (e.code == "email-already-in-use") {
        message = "البريد الإلكتروني مستخدم بالفعل";
      } else if (e.code == "weak-password") {
        message = "كلمة المرور ضعيفة";
      } else if (e.code == "invalid-email") {
        message = "البريد الإلكتروني غير صالح";
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("حدث خطأ: $e")),
      );
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
        elevation: 0,
        centerTitle: true,
        title: Text(tr("create_account_title"), style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const Icon(Icons.directions_car, color: Colors.blue, size: 80),
                const SizedBox(height: 15),
                const Center(
                  child: Text(
                    "DriveEasy",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: tr("full_name"),
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty) ? "أدخل الاسم الكامل" : null,
                ),
                const SizedBox(height: 20),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textCapitalization: TextCapitalization.none,
                    textAlign: TextAlign.left,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: tr("email"),
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return "أدخل البريد الإلكتروني";
                      if (!value.trim().contains("@")) return "البريد الإلكتروني غير صحيح";
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: tr("phone"),
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty) ? "أدخل رقم الهاتف" : null,
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
                      if (value == null || value.isEmpty) return "أدخل كلمة المرور";
                      if (value.length < 6) return "يجب أن تكون كلمة المرور 6 أحرف على الأقل";
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextFormField(
                    controller: confirmPasswordController,
                    obscureText: hideConfirmPassword,
                    textAlign: TextAlign.left,
                    decoration: InputDecoration(
                      labelText: tr("confirm_password"),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(hideConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => hideConfirmPassword = !hideConfirmPassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    validator: (value) =>
                        (value == null || value.isEmpty) ? "أكد كلمة المرور" : null,
                  ),
                ),
                const SizedBox(height: 25),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(tr("account_type"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                RadioListTile(
                  title: Text(tr("student")),
                  value: "student",
                  groupValue: selectedRole,
                  onChanged: (value) => setState(() => selectedRole = value!),
                ),
                RadioListTile(
                  title: Text(tr("teacher")),
                  value: "teacher",
                  groupValue: selectedRole,
                  onChanged: (value) => setState(() => selectedRole = value!),
                ),
                if (selectedRole == "teacher") ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      tr("license_type_teaching"),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection("license_types")
                        .orderBy("createdAt")
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final options = snapshot.data!.docs
                          .where((doc) => (doc.data() as Map<String, dynamic>)["isDeleted"] != true)
                          .toList();

                      return DropdownButtonFormField<String>(
                        value: teacherLicenseType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          hintText: "اختر نوع الرخصة",
                        ),
                        items: options
                            .map((doc) {
                              final licenseName =
                                  ((doc.data() as Map<String, dynamic>)["name"] ?? "").toString();
                              return DropdownMenuItem(
                                value: licenseName,
                                child: Text(licenseName.isNotEmpty ? licenseName : "بدون اسم"),
                              );
                            })
                            .toList(),
                        onChanged: (value) => setState(() => teacherLicenseType = value),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "المدرسة التي تنتمي إليها",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection("schools")
                        .orderBy("createdAt")
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final schools = snapshot.data!.docs;

                      if (schools.isEmpty) {
                        return const Text(
                          "لا يوجد مدارس مسجلة بعد بالنظام، تواصل مع الإدارة",
                          style: TextStyle(color: Colors.red, fontSize: 12.5),
                        );
                      }

                      return DropdownButtonFormField<String>(
                        value: teacherSchoolId,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          hintText: "اختر المدرسة",
                        ),
                        items: schools
                            .map((doc) => DropdownMenuItem(
                                  value: doc.id,
                                  child: Text((doc.data() as Map<String, dynamic>)["name"] ?? ""),
                                ))
                            .toList(),
                        onChanged: (value) => setState(() {
                          teacherSchoolId = value;
                          teacherSchoolName = (schools.firstWhere((d) => d.id == value).data()
                              as Map<String, dynamic>)["name"];
                        }),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : registerUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "إنشاء حساب",
                            style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text("بالتسجيل فإنك توافق على "),
                    Text("الشروط والأحكام", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

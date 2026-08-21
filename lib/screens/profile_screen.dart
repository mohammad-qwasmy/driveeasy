import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'login_screen.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'teacher_monthly_lessons_screen.dart';
import '../services/app_language.dart';
import '../services/support_contact.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isLoading = true;
  bool isUploadingPhoto = false;

  String name = "";
  String email = "";
  String phone = "";
  String city = "";
  String licenseType = "";
  String schoolName = "";
  String role = "";
  String profileImageBase64 = "";

  int bookings = 0;
  int lessons = 0;
  double rating = 0;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DocumentSnapshot doc =
        await FirebaseFirestore.instance.collection("users").doc(user.uid).get();

    final data = doc.data() as Map<String, dynamic>? ?? {};
    String fetchedSchoolName = "";
    final schoolId = data["schoolId"] ?? "";
    if (data["role"] == "teacher" && schoolId.toString().isNotEmpty) {
      final schoolDoc = await FirebaseFirestore.instance.collection("schools").doc(schoolId).get();
      fetchedSchoolName = (schoolDoc.data() as Map<String, dynamic>?)?["name"] ?? "";
    }

    if (!mounted) return;

    final userData = doc.data() as Map<String, dynamic>? ?? {};

    setState(() {
      name = userData["name"] ?? "";
      email = userData["email"] ?? "";
      phone = userData["phone"] ?? "";
      city = userData["city"] ?? "";
      licenseType = userData["licenseType"] ?? "";
      schoolName = fetchedSchoolName;
      role = userData["role"] ?? "";
      profileImageBase64 = userData["profileImage"] ?? "";

      bookings = userData["bookings"] ?? 0;
      lessons = userData["lessons"] ?? 0;
      rating = ((userData["rating"] ?? 0) as num).toDouble();

      isLoading = false;
    });
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        imageQuality: 55,
      );

      if (picked == null) return;

      setState(() => isUploadingPhoto = true);

      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);

      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance.collection("users").doc(user.uid).update({
        "profileImage": base64Image,
      });

      if (!mounted) return;
      setState(() {
        profileImageBase64 = base64Image;
        isUploadingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر تحميل الصورة: $e")),
      );
    }
  }

  Future<void> _showLanguagePicker() async {
    final options = {"ar": "العربية", "en": "English", "he": "עברית"};

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr("choose_language")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries
              .map((e) => RadioListTile<String>(
                    title: Text(e.value),
                    value: e.key,
                    groupValue: AppLanguage.code.value,
                    onChanged: (v) => Navigator.pop(ctx, v),
                  ))
              .toList(),
        ),
      ),
    );

    if (chosen != null) {
      await AppLanguage.setLanguage(chosen);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text("حذف الحساب")),
          ],
        ),
        content: const Text(
          "سيتم تعطيل حسابك فوراً ولن تتمكن من استخدام التطبيق به.\n\n"
          "بياناتك تبقى محفوظة لمدة 30 يوماً فقط — يمكنك خلال هذه الفترة استرجاع حسابك بنفسك "
          "بمجرد تسجيل الدخول به مرة أخرى.\n\n"
          "بعد مرور 30 يوماً، سيتم حذف حسابك وكل بياناتك نهائياً بشكل لا يمكن التراجع عنه.",
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("نعم، احذف حسابي", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      await FirebaseFirestore.instance.collection("users").doc(user.uid).update({
        "isDeleted": true,
        "deletedAt": Timestamp.fromDate(now),
        "purgeAt": Timestamp.fromDate(now.add(const Duration(days: 30))),
      });

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      Navigator.pop(context); // close loading dialog

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر حذف الحساب: $e")),
      );
    }
  }

  String get roleLabel {
    switch (role) {
      case "teacher":
        return tr("teacher");
      case "admin":
        return tr("admin");
      case "super_admin":
        return tr("super_admin");
      default:
        return tr("student");
    }
  }

  bool get isTeacherOrStudent => role == "teacher" || role == "student";

  Widget buildInfoCard(IconData icon, String title, String value) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        subtitle: Text(value.isEmpty ? tr("not_available") : value),
      ),
    );
  }

  Widget buildStatCard(
    String title,
    String value,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Card(
        elevation: 3,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Column(
              children: [
                Icon(icon, size: 35, color: Colors.blue),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(title, textAlign: TextAlign.center),
                if (onTap != null) ...[
                  const SizedBox(height: 4),
                  const Text(
                    "عرض التفاصيل",
                    style: TextStyle(fontSize: 10.5, color: Colors.blue),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    ImageProvider? avatarImage;
    if (profileImageBase64.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(profileImageBase64));
      } catch (_) {
        avatarImage = null;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr("profile_title")), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 55,
                  backgroundColor: Colors.blue,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? const Icon(Icons.person, size: 60, color: Colors.white)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: isUploadingPhoto ? null : _pickAndUploadPhoto,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xff1565C0),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: isUploadingPhoto
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.add, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(
              roleLabel,
              style: const TextStyle(color: Colors.grey, fontSize: 18),
            ),
            const SizedBox(height: 25),
            buildInfoCard(Icons.email, tr("email"), email),
            buildInfoCard(Icons.phone, tr("phone"), phone),
            buildInfoCard(Icons.location_city, tr("city"), city),
            if (isTeacherOrStudent) buildInfoCard(Icons.badge, tr("license_type"), licenseType),
            if (role == "teacher") buildInfoCard(Icons.school, "المدرسة", schoolName),
            if (isTeacherOrStudent) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  buildStatCard(
                    tr("lessons_count"),
                    lessons.toString(),
                    Icons.menu_book,
                    onTap: role == "teacher"
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TeacherMonthlyLessonsScreen(),
                              ),
                            );
                          }
                        : null,
                  ),
                  const SizedBox(width: 12),
                  buildStatCard(
                    role == "teacher" ? tr("rating") : tr("bookings"),
                    role == "teacher" ? rating.toStringAsFixed(1) : bookings.toString(),
                    role == "teacher" ? Icons.star : Icons.calendar_month,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.language, color: Colors.blue),
                title: Text(tr("language")),
                subtitle: Text({"ar": "العربية", "en": "English", "he": "עברית"}[AppLanguage.code.value] ?? ""),
                trailing: const Icon(Icons.chevron_left),
                onTap: _showLanguagePicker,
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                  );
                  loadProfile();
                },
                icon: const Icon(Icons.edit),
                label: Text(tr("edit_info")),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                  );
                },
                icon: const Icon(Icons.lock),
                label: Text(tr("change_password")),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(tr("logout")),
                      content: const Text("هل أنت متأكد أنك تريد تسجيل الخروج؟"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text("إلغاء"),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(tr("logout"), style: const TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );

                  if (confirmed != true) return;

                  await FirebaseAuth.instance.signOut();

                  if (!context.mounted) return;

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout),
                label: Text(tr("logout")),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade700),
                onPressed: () => openWhatsAppSupport(),
                icon: const Icon(Icons.chat),
                label: const Text("تواصل معنا عبر واتساب"),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: _confirmDeleteAccount,
                icon: const Icon(Icons.delete_forever),
                label: const Text("حذف الحساب"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

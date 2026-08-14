import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lets the current user (student or teacher) edit their own stored profile
/// fields in Firestore: name, phone, city, and license type (for a teacher,
/// this is the license type they teach; for a student, the one they're
/// learning).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final cityController = TextEditingController();
  String? licenseType;
  String role = "student";
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await FirebaseFirestore.instance.collection("users").doc(user.uid).get();
    final data = doc.data() as Map<String, dynamic>? ?? {};

    nameController.text = data["name"] ?? "";
    phoneController.text = data["phone"] ?? "";
    cityController.text = data["city"] ?? "";
    licenseType = (data["licenseType"] ?? "").toString().isEmpty ? null : data["licenseType"];
    role = data["role"] ?? "student";

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Future<void> _save() async {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("أدخل الاسم")),
      );
      return;
    }

    setState(() => isSaving = true);

    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection("users").doc(user.uid).update({
      "name": nameController.text.trim(),
      "phone": phoneController.text.trim(),
      "city": cityController.text.trim(),
      if (licenseType != null) "licenseType": licenseType,
    });

    if (!mounted) return;
    setState(() => isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم حفظ التعديلات بنجاح")),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("تعديل البيانات")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "الاسم الكامل",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "رقم الهاتف",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: cityController,
              decoration: const InputDecoration(
                labelText: "المدينة",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("license_types")
                  .orderBy("createdAt")
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 56,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final options = snapshot.data!.docs;

                return DropdownButtonFormField<String>(
                  value: licenseType,
                  decoration: InputDecoration(
                    labelText: role == "teacher" ? "نوع الرخصة التي تدرّسها" : "نوع الرخصة",
                    border: const OutlineInputBorder(),
                  ),
                  items: options
                      .map((doc) => DropdownMenuItem(
                            value: doc["name"] as String,
                            child: Text(doc["name"]),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => licenseType = value),
                );
              },
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isSaving ? null : _save,
                child: isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("حفظ التعديلات"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

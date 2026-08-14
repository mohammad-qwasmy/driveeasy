import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'teacher_screen.dart';

/// Lets a student pick a license type to start (or add) a teacher link for.
/// A student can hold more than one license type at once (one teacher per
/// type), so this only excludes types they already have an active or
/// pending relationship for — it doesn't overwrite a single "the" license
/// type on their account anymore.
class LicenseTypeScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const LicenseTypeScreen({super.key, required this.schoolId, required this.schoolName});

  @override
  State<LicenseTypeScreen> createState() => _LicenseTypeScreenState();
}

class _LicenseTypeScreenState extends State<LicenseTypeScreen> {
  String selectedLicense = "";
  String selectedName = "";

  Future<void> _continue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Keep this as informational/profile display only — it no longer
    // drives booking logic since a student can have several license types.
    await FirebaseFirestore.instance.collection("users").doc(user.uid).update({
      "licenseType": selectedName,
    });

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherScreen(
          licenseType: selectedName,
          schoolId: widget.schoolId,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("اختر نوع الرخصة"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("student_teacher_links")
            .where("studentId", isEqualTo: studentId)
            .where("status", whereIn: ["active", "pending"])
            .snapshots(),
        builder: (context, linksSnap) {
          final existingTypes = (linksSnap.data?.docs ?? [])
              .map((d) => (d.data() as Map<String, dynamic>)["licenseType"] as String? ?? "")
              .toSet();

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("license_types")
                .orderBy("createdAt")
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final licenses = snapshot.data!.docs
                  .where((doc) => !existingTypes.contains(doc["name"]))
                  .toList();

              if (licenses.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      "أنت مرتبط بالفعل بجميع أنواع الرخص المتاحة",
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: licenses.length,
                        itemBuilder: (context, index) {
                          final license = licenses[index];
                          bool selected = selectedLicense == license.id;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 15),
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.directions_car)),
                              title: Text(license["name"]),
                              trailing: selected
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : null,
                              onTap: () {
                                setState(() {
                                  selectedLicense = license.id;
                                  selectedName = license["name"];
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: selectedLicense.isEmpty ? null : _continue,
                        child: const Text("التالي", style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

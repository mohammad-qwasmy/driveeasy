import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';

/// Shows the student's driving curriculum and which steps their teacher has
/// marked as completed. Read-only from the student's side. Since a student
/// can have more than one teacher (one per license type), this first shows
/// a chooser if there's more than one active link.
class MyPlanScreen extends StatefulWidget {
  const MyPlanScreen({super.key});

  @override
  State<MyPlanScreen> createState() => _MyPlanScreenState();
}

class _MyPlanScreenState extends State<MyPlanScreen> {
  String? selectedLinkId;
  String? selectedLicenseType;

  @override
  Widget build(BuildContext context) {
    final studentId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedLicenseType == null ? "خطتي" : "خطتي - $selectedLicenseType"),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("student_teacher_links")
            .where("studentId", isEqualTo: studentId)
            .where("status", isEqualTo: "active")
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final links = snapshot.data!.docs;

          if (links.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text("لا يوجد لديك خطة بعد — يجب الارتباط بمدرب أولاً", textAlign: TextAlign.center),
              ),
            );
          }

          // Auto-select if there's only one.
          if (links.length == 1 && selectedLinkId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                selectedLinkId = links.first.id;
                selectedLicenseType = (links.first.data() as Map<String, dynamic>)["licenseType"];
              });
            });
            return const Center(child: CircularProgressIndicator());
          }

          if (selectedLinkId == null) {
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: links.length,
              itemBuilder: (context, index) {
                final data = links[index].data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.flag_rounded, color: Color(0xff1565C0)),
                    title: Text("خطة رخصة ${data["licenseType"] ?? ""}"),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => setState(() {
                      selectedLinkId = links[index].id;
                      selectedLicenseType = data["licenseType"];
                    }),
                  ),
                );
              },
            );
          }

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: ensureStudentPlan(selectedLinkId!),
            builder: (context, planSnapshot) {
              if (!planSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final steps = planSnapshot.data!;
              final done = steps.where((s) => s["done"] == true).length;
              final percent = steps.isEmpty ? 0.0 : done / steps.length;

              return Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LinearProgressIndicator(value: percent, minHeight: 12),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "${(percent * 100).round()}% مكتمل ($done من ${steps.length})",
                              style: const TextStyle(
                                color: Color(0xff1565C0),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: ListView.builder(
                        itemCount: steps.length,
                        itemBuilder: (context, index) {
                          final step = steps[index];
                          final isDone = step["done"] == true;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: Icon(
                                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: isDone ? Colors.green : Colors.grey,
                              ),
                              title: Text(
                                step["title"] ?? "",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isDone ? Colors.black87 : Colors.grey.shade700,
                                ),
                              ),
                              trailing: Text(
                                "${index + 1}",
                                style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
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

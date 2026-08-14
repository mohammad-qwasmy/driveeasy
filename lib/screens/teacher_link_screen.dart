import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'school_selection_screen.dart';
import '../services/app_language.dart';

/// Shows every teacher relationship the student has (one per license
/// type — a student can hold several license types, each with its own
/// teacher), plus pending requests, plus a button to start a new one for a
/// license type they don't have yet.
class TeacherLinkScreen extends StatelessWidget {
  const TeacherLinkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final studentId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: Text(tr("teacher_link")), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("student_teacher_links")
            .where("studentId", isEqualTo: studentId)
            .snapshots(),
        builder: (context, linksSnap) {
          final links = (linksSnap.data?.docs ?? [])
              .where((d) => (d.data() as Map<String, dynamic>)["status"] != "removed_by_teacher" &&
                  (d.data() as Map<String, dynamic>)["status"] != "removed_by_student")
              .toList();

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("student_teacher_requests")
                .where("studentId", isEqualTo: studentId)
                .where("status", isEqualTo: "pending")
                .snapshots(),
            builder: (context, reqSnap) {
              final pendingRequests = reqSnap.data?.docs ?? [];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (links.isEmpty && pendingRequests.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.person_search_rounded, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            "لست مرتبطًا بأي مدرب بعد",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "اختر نوع رخصة وابدأ بالبحث عن مدرب",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ...links.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data["status"] ?? "active";
                    final licenseType = data["licenseType"] ?? "";

                    Color statusColor = Colors.green;
                    String statusText = "نشط";
                    if (status == "passed") {
                      statusColor = Colors.blue;
                      statusText = "تم النجاح";
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection("users")
                            .doc(data["teacherId"])
                            .get(),
                        builder: (context, teacherSnap) {
                          final teacherName =
                              (teacherSnap.data?.data() as Map<String, dynamic>?)?["name"] ?? "...";
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xff1565C0),
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(teacherName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("رخصة: $licenseType"),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11.5),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                  ...pendingRequests.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: const Color(0xffFFF4E5),
                      child: ListTile(
                        leading: const Icon(Icons.hourglass_top_rounded, color: Colors.orange),
                        title: Text("${data["teacherName"] ?? "مدرب"} · ${data["licenseType"] ?? ""}"),
                        subtitle: const Text("طلبك قيد المراجعة"),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          tooltip: "إلغاء الطلب",
                          onPressed: () => doc.reference.delete(),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SchoolSelectionScreen()),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text("إضافة نوع رخصة جديد"),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

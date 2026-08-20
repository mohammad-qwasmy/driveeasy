import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';

/// Lets a teacher send a real in-app notification to their own students —
/// either everyone linked to them, or a hand-picked subset. Only students
/// with an "active" link to this teacher are shown, same list used by
/// "طلابي".
class TeacherMessageStudentsScreen extends StatefulWidget {
  const TeacherMessageStudentsScreen({super.key});

  @override
  State<TeacherMessageStudentsScreen> createState() =>
      _TeacherMessageStudentsScreenState();
}

class _TeacherMessageStudentsScreenState
    extends State<TeacherMessageStudentsScreen> {
  final TextEditingController titleController =
      TextEditingController(text: "رسالة من المدرب");
  final TextEditingController bodyController = TextEditingController();

  bool sendToAll = true;
  final Set<String> selectedStudentIds = {};
  bool isSending = false;

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  Future<void> _send(List<Map<String, dynamic>> allStudents) async {
    if (bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اكتب نص الرسالة أولاً")),
      );
      return;
    }

    final targets = sendToAll
        ? allStudents
        : allStudents.where((s) => selectedStudentIds.contains(s["id"])).toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اختر طالبًا واحدًا على الأقل")),
      );
      return;
    }

    setState(() => isSending = true);

    try {
      for (final student in targets) {
        await sendNotification(
          userId: student["id"],
          title: titleController.text.trim().isEmpty
              ? "رسالة من المدرب"
              : titleController.text.trim(),
          body: bodyController.text.trim(),
          type: "teacher_message",
        );
      }

      if (!mounted) return;
      setState(() => isSending = false);
      bodyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم إرسال الرسالة إلى ${targets.length} طالب")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر الإرسال: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xffF5F9FF),
      appBar: AppBar(title: const Text("مراسلة الطلاب"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("student_teacher_links")
            .where("teacherId", isEqualTo: teacherId)
            .where("status", isEqualTo: "active")
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final links = snapshot.data!.docs;

          if (links.isEmpty) {
            return const Center(
              child: Text("لا يوجد طلاب مرتبطون بك بعد", style: TextStyle(fontSize: 16)),
            );
          }

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _resolveStudents(links),
            builder: (context, studentsSnap) {
              if (!studentsSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final students = studentsSnap.data!;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: "عنوان الرسالة",
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: bodyController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: "نص الرسالة",
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("إرسال إلى كل طلابي"),
                          value: sendToAll,
                          onChanged: (v) => setState(() => sendToAll = v),
                        ),
                      ],
                    ),
                  ),
                  if (!sendToAll)
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final s = students[index];
                          final id = s["id"] as String;
                          return CheckboxListTile(
                            value: selectedStudentIds.contains(id),
                            title: Text(s["name"] ?? "طالب"),
                            subtitle: Text(s["licenseType"] ?? ""),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  selectedStudentIds.add(id);
                                } else {
                                  selectedStudentIds.remove(id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    )
                  else
                    const Expanded(
                      child: Center(
                        child: Text(
                          "سيتم إرسال الرسالة لجميع طلابك الحاليين",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        onPressed: isSending ? null : () => _send(students),
                        icon: isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send, color: Colors.white),
                        label: const Text("إرسال", style: TextStyle(color: Colors.white)),
                      ),
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

  Future<List<Map<String, dynamic>>> _resolveStudents(
      List<QueryDocumentSnapshot> links) async {
    final results = <Map<String, dynamic>>[];
    for (final link in links) {
      final linkData = link.data() as Map<String, dynamic>;
      final studentId = linkData["studentId"] as String?;
      if (studentId == null) continue;

      final userDoc =
          await FirebaseFirestore.instance.collection("users").doc(studentId).get();
      final userData = userDoc.data();
      if (userData == null) continue;

      results.add({
        "id": studentId,
        "name": userData["name"] ?? "طالب",
        "licenseType": linkData["licenseType"] ?? "",
      });
    }
    return results;
  }
}

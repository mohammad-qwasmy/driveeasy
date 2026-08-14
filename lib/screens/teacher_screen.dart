import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lets a student browse teachers for one specific [licenseType] and send a
/// link request. A student can have several license types over time, each
/// with its own teacher, so this always operates on one type at a time.
class TeacherScreen extends StatefulWidget {
  final String licenseType;
  final String schoolId;
  final String schoolName;

  const TeacherScreen({
    super.key,
    required this.licenseType,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<TeacherScreen> createState() => _TeacherScreenState();
}

class _TeacherScreenState extends State<TeacherScreen> {
  String? selectedTeacherId;
  String? selectedTeacherName;

  Future<void> sendRequest() async {
    if (selectedTeacherId == null) return;

    final studentId = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection("student_teacher_requests").add({
      "studentId": studentId,
      "teacherId": selectedTeacherId,
      "teacherName": selectedTeacherName,
      "licenseType": widget.licenseType,
      "schoolId": widget.schoolId,
      "status": "pending",
      "createdAt": Timestamp.now(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم إرسال طلب الارتباط بنجاح")),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("مدربو ${widget.licenseType} - ${widget.schoolName}"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .where("role", isEqualTo: "teacher")
            .where("isVerified", isEqualTo: true)
            .where("licenseType", isEqualTo: widget.licenseType)
            .where("schoolId", isEqualTo: widget.schoolId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "لا يوجد مدربون بهذه المدرسة متاحون لنوع الرخصة الذي اخترته حالياً",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final teachers = snapshot.data!.docs;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: teachers.length,
                    itemBuilder: (context, index) {
                      final teacher = teachers[index];
                      final data = teacher.data() as Map<String, dynamic>;
                      bool selected = selectedTeacherId == teacher.id;

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(
                            color: selected ? Colors.blue : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(data["name"] ?? ""),
                          subtitle: Text(
                            "${data["phone"] ?? ""}"
                            "${(data["city"] ?? "").toString().isNotEmpty ? " · ${data["city"]}" : ""}",
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle, color: Colors.blue)
                              : const Icon(Icons.circle_outlined),
                          onTap: () {
                            setState(() {
                              selectedTeacherId = teacher.id;
                              selectedTeacherName = data["name"];
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedTeacherId == null ? null : sendRequest,
                    child: const Text("إرسال طلب ارتباط"),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';
import '../widgets/count_label.dart';

class TeacherRequestsScreen extends StatefulWidget {
  const TeacherRequestsScreen({super.key});

  @override
  State<TeacherRequestsScreen> createState() => _TeacherRequestsScreenState();
}

class _TeacherRequestsScreenState extends State<TeacherRequestsScreen> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;
    final requestsStream = FirebaseFirestore.instance
        .collection("student_teacher_requests")
        .where("teacherId", isEqualTo: teacherId)
        .where("status", isEqualTo: "pending")
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: CountLabel(text: "طلبات الارتباط", stream: requestsStream),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: "ابحث عن طالب بالاسم أو الهاتف",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() => searchQuery = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: requestsStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("لا توجد طلبات ارتباط"));
                }

                final requests = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    final requestData = request.data() as Map<String, dynamic>;
                    final licenseType = requestData["licenseType"] ?? "";
                    final schoolId = requestData["schoolId"] ?? "";

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection("users")
                          .doc(requestData["studentId"])
                          .get(),
                      builder: (context, studentSnapshot) {
                        if (!studentSnapshot.hasData) {
                          return const SizedBox();
                        }

                        final student = studentSnapshot.data!;
                        final studentData = student.data() as Map<String, dynamic>?;
                        final name = studentData?["name"] ?? "";
                        final phone = studentData?["phone"] ?? "";

                        if (searchQuery.isNotEmpty) {
                          final matches = name.toString().toLowerCase().contains(searchQuery) ||
                              phone.toString().toLowerCase().contains(searchQuery);
                          if (!matches) return const SizedBox.shrink();
                        }

                        return Card(
                          margin: const EdgeInsets.all(10),
                          child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 5),
                                Text(phone),
                                if (licenseType.toString().isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text("نوع الرخصة: $licenseType", style: const TextStyle(color: Colors.blue)),
                                ],
                                const SizedBox(height: 15),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                        icon: const Icon(Icons.check),
                                        label: const Text("قبول"),
                                        onPressed: () async {
                                          await FirebaseFirestore.instance
                                              .collection("student_teacher_requests")
                                              .doc(request.id)
                                              .update({"status": "approved"});

                                          await FirebaseFirestore.instance
                                              .collection("student_teacher_links")
                                              .add({
                                            "studentId": student.id,
                                            "teacherId": teacherId,
                                            "licenseType": licenseType,
                                            "schoolId": schoolId,
                                            "status": "active",
                                            "requiredLessons": 0,
                                            "testDate": "",
                                            "testTime": "",
                                            "createdAt": Timestamp.now(),
                                          });

                                          await sendNotification(
                                            userId: student.id,
                                            title: "تم قبول طلب الارتباط",
                                            body: "أصبحت مرتبطاً الآن بالمدرب لرخصة $licenseType، يمكنك حجز دروسك.",
                                            type: "link_approved",
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        icon: const Icon(Icons.close),
                                        label: const Text("رفض"),
                                        onPressed: () async {
                                          await FirebaseFirestore.instance
                                              .collection("student_teacher_requests")
                                              .doc(request.id)
                                              .update({"status": "rejected"});
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

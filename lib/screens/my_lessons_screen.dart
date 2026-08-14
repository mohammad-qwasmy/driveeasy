import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';
import '../widgets/count_label.dart';

/// Two tabs: lessons actually attended vs. booked-but-not-yet-taken. Since a
/// student can have more than one teacher (one per license type), stats and
/// lists are grouped per teacher so they never mix together.
class MyLessonsScreen extends StatelessWidget {
  const MyLessonsScreen({super.key});

  Widget _lessonTile(Map<String, dynamic> data, {required bool taken}) {
    final dateStr = data["date"] ?? "";
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          taken ? Icons.check_circle : Icons.hourglass_top_rounded,
          color: taken ? Colors.green : Colors.orange,
        ),
        title: Text(dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : (data["day"] ?? "")),
        subtitle: Text("${data["time"]} · ${data["price"]} ₪"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentId = FirebaseAuth.instance.currentUser!.uid;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("دروسي"),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(
                child: CountLabel(
                  text: "دروس أخذتها",
                  stream: FirebaseFirestore.instance
                      .collection("bookings")
                      .where("studentId", isEqualTo: studentId)
                      .where("attendance", isEqualTo: "attended")
                      .snapshots(),
                ),
              ),
              Tab(
                child: CountLabel(
                  text: "حجوزات لم تؤخذ بعد",
                  stream: FirebaseFirestore.instance
                      .collection("bookings")
                      .where("studentId", isEqualTo: studentId)
                      .where("status", isEqualTo: "approved")
                      .where("attendance", isEqualTo: null)
                      .snapshots(),
                ),
              ),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("student_teacher_links")
              .where("studentId", isEqualTo: studentId)
              .snapshots(),
          builder: (context, linksSnap) {
            if (!linksSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final links = linksSnap.data!.docs;

            if (links.isEmpty) {
              return const Center(
                child: Text("لا يوجد لديك مدرب مرتبط بعد", style: TextStyle(color: Colors.grey)),
              );
            }

            return TabBarView(
              children: [
                _AttendedTab(studentId: studentId, links: links),
                _PendingTab(studentId: studentId, links: links),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AttendedTab extends StatelessWidget {
  final String studentId;
  final List<QueryDocumentSnapshot> links;

  const _AttendedTab({required this.studentId, required this.links});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: links.map((linkDoc) {
        final linkData = linkDoc.data() as Map<String, dynamic>;
        final teacherId = linkData["teacherId"] as String;
        final licenseType = linkData["licenseType"] ?? "";
        final requiredLessons = linkData["requiredLessons"] ?? 0;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("bookings")
              .where("studentId", isEqualTo: studentId)
              .where("teacherId", isEqualTo: teacherId)
              .where("attendance", isEqualTo: "attended")
              .snapshots(),
          builder: (context, snapshot) {
            final lessons = [...(snapshot.data?.docs ?? [])]..sort((a, b) {
              final da = (a.data() as Map<String, dynamic>)["date"] ?? "";
              final db = (b.data() as Map<String, dynamic>)["date"] ?? "";
              return db.toString().compareTo(da.toString());
            });

            final attendedCount = lessons.length;
            final remaining = requiredLessons > 0 ? (requiredLessons - attendedCount).clamp(0, 999) : null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "رخصة $licenseType",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1565C0)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Column(
                              children: [
                                Text("$attendedCount",
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xff1565C0))),
                                const SizedBox(height: 3),
                                const Text("دروس أخذها", style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Column(
                              children: [
                                Text(remaining == null ? "—" : "$remaining",
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
                                const SizedBox(height: 3),
                                const Text("دروس متبقية", style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (lessons.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text("لم تأخذ أي دروس بعد", style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ...lessons.map((doc) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Builder(builder: (context) {
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.check_circle, color: Colors.green),
                                title: Text(
                                  ((doc.data() as Map<String, dynamic>)["date"] ?? "").toString().isNotEmpty
                                      ? formatIsoDateArabic((doc.data() as Map<String, dynamic>)["date"])
                                      : ((doc.data() as Map<String, dynamic>)["day"] ?? ""),
                                ),
                                subtitle: Text(
                                  "${(doc.data() as Map<String, dynamic>)["time"]} · ${(doc.data() as Map<String, dynamic>)["price"]} ₪",
                                ),
                              ),
                            );
                          }),
                        )),
                ],
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

class _PendingTab extends StatelessWidget {
  final String studentId;
  final List<QueryDocumentSnapshot> links;

  const _PendingTab({required this.studentId, required this.links});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: links.map((linkDoc) {
        final linkData = linkDoc.data() as Map<String, dynamic>;
        final teacherId = linkData["teacherId"] as String;
        final licenseType = linkData["licenseType"] ?? "";

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("bookings")
              .where("studentId", isEqualTo: studentId)
              .where("teacherId", isEqualTo: teacherId)
              .where("status", isEqualTo: "approved")
              .where("attendance", isEqualTo: null)
              .snapshots(),
          builder: (context, snapshot) {
            final pending = [...(snapshot.data?.docs ?? [])]..sort((a, b) {
              final da = (a.data() as Map<String, dynamic>)["date"] ?? "";
              final db = (b.data() as Map<String, dynamic>)["date"] ?? "";
              return da.toString().compareTo(db.toString());
            });

            if (pending.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "رخصة $licenseType",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1565C0)),
                  ),
                  const SizedBox(height: 8),
                  ...pending.map((doc) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.hourglass_top_rounded, color: Colors.orange),
                            title: Text(
                              ((doc.data() as Map<String, dynamic>)["date"] ?? "").toString().isNotEmpty
                                  ? formatIsoDateArabic((doc.data() as Map<String, dynamic>)["date"])
                                  : ((doc.data() as Map<String, dynamic>)["day"] ?? ""),
                            ),
                            subtitle: Text(
                              "${(doc.data() as Map<String, dynamic>)["time"]} · ${(doc.data() as Map<String, dynamic>)["price"]} ₪",
                            ),
                          ),
                        ),
                      )),
                ],
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Admin overview of every student: their own info, plus which teacher(s)
/// and school(s) they're linked to. A student can have more than one
/// active link (one per license type), so each is shown as its own chip
/// under the student's card.
class AdminStudentsScreen extends StatefulWidget {
  const AdminStudentsScreen({super.key});

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  String searchQuery = "";

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat("d/M/yyyy").format(ts.toDate());
    }
    return "غير متوفر";
  }

  Widget _detailLine(IconData icon, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// One student's teacher/school links, fetched only when the card is
  /// visible. A student can be linked to more than one teacher (one per
  /// license type), so this returns a list, not a single result.
  Widget _linksSection(String studentId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("student_teacher_links")
          .where("studentId", isEqualTo: studentId)
          .where("status", isEqualTo: "active")
          .snapshots(),
      builder: (context, linkSnap) {
        final links = linkSnap.data?.docs ?? [];
        if (links.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              "غير مرتبط بأي مدرب حالياً",
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: links.map((linkDoc) {
            final linkData = linkDoc.data() as Map<String, dynamic>;
            final teacherId = (linkData["teacherId"] ?? "").toString();
            final licenseType = (linkData["licenseType"] ?? "").toString();

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection("users").doc(teacherId).get(),
              builder: (context, teacherSnap) {
                final teacherData = teacherSnap.data?.data() as Map<String, dynamic>?;
                final teacherName = teacherData?["name"] ?? "...";
                final schoolId = (teacherData?["schoolId"] ?? "").toString();

                return Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xffF2F6FC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, size: 15, color: Color(0xff1565C0)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "$teacherName · $licenseType",
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (schoolId.isEmpty)
                        const Text("بدون مدرسة", style: TextStyle(fontSize: 11, color: Colors.grey))
                      else
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection("schools").doc(schoolId).get(),
                          builder: (context, schoolSnap) {
                            final schoolName = (schoolSnap.data?.data() as Map<String, dynamic>?)?["name"] ?? "...";
                            return Text(
                              schoolName,
                              style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("الطلاب"), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
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
              stream: FirebaseFirestore.instance
                  .collection("users")
                  .where("role", isEqualTo: "student")
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        "تعذر تحميل الطلاب: ${snapshot.error}",
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final students = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data["isDeleted"] == true) return false;
                  if (searchQuery.isEmpty) return true;
                  final name = (data["name"] ?? "").toString().toLowerCase();
                  final phone = (data["phone"] ?? "").toString().toLowerCase();
                  return name.contains(searchQuery) || phone.contains(searchQuery);
                }).toList();

                if (students.isEmpty) {
                  return const Center(child: Text("لا يوجد طلاب", style: TextStyle(color: Colors.grey)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final studentDoc = students[index];
                    final student = studentDoc.data() as Map<String, dynamic>;

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Color(0xff1565C0),
                                  child: Icon(Icons.person, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    student["name"] ?? "",
                                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _detailLine(Icons.email, student["email"] ?? ""),
                            _detailLine(Icons.phone, student["phone"] ?? ""),
                            _detailLine(Icons.location_city, student["city"] ?? ""),
                            _detailLine(Icons.calendar_today, _formatDate(student["createdAt"])),
                            const SizedBox(height: 6),
                            const Text(
                              "المدرب والمدرسة",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            _linksSection(studentDoc.id),
                          ],
                        ),
                      ),
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

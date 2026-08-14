import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Shows everything about a single school: its name, and the full list of
/// teachers that belong to it (with their contact info, license type and
/// verification status).
class SchoolDetailsScreen extends StatelessWidget {
  final String schoolId;
  final String schoolName;

  const SchoolDetailsScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(schoolName), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .where("role", isEqualTo: "teacher")
            .where("schoolId", isEqualTo: schoolId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final teachers = snapshot.data!.docs;

          if (teachers.isEmpty) {
            return const Center(
              child: Text(
                "لا يوجد مدربون في هذه المدرسة حتى الآن",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: teachers.length,
            itemBuilder: (context, index) {
              final teacher = teachers[index].data() as Map<String, dynamic>;
              final isBlocked = teacher["isBlocked"] == true;
              final isVerified = teacher["isVerified"] == true;

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
                              teacher["name"] ?? "",
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _detailLine(Icons.email, teacher["email"] ?? ""),
                      _detailLine(Icons.phone, teacher["phone"] ?? ""),
                      _detailLine(Icons.location_city, teacher["city"] ?? ""),
                      _detailLine(Icons.badge, teacher["licenseType"] ?? ""),
                      _detailLine(Icons.calendar_today, _formatDate(teacher["createdAt"])),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isBlocked ? Colors.red.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isBlocked ? Icons.cancel : Icons.verified,
                              color: isBlocked ? Colors.red : Colors.green,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isBlocked
                                  ? "معطّل"
                                  : (isVerified ? "موثّق" : "بانتظار التوثيق"),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isBlocked ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

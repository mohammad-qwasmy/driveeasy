import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Shows how many lessons the teacher actually gave, broken down by month.
/// Only bookings marked "attended" count — a booking marked "لم يحضر" (not
/// attended) is not counted as a lesson given.
class TeacherMonthlyLessonsScreen extends StatelessWidget {
  const TeacherMonthlyLessonsScreen({super.key});

  static const List<String> _arabicMonths = [
    "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
    "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
  ];

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("عدد الدروس شهرياً"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("bookings")
            .where("teacherId", isEqualTo: teacherId)
            .where("attendance", isEqualTo: "attended")
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text("لم تُسجَّل أي دروس حضرها الطلاب بعد", style: TextStyle(color: Colors.grey)),
            );
          }

          final Map<String, int> byMonth = {};
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data["date"] ?? "") as String;
            if (date.length < 7) continue;
            final monthKey = date.substring(0, 7); // yyyy-MM
            byMonth[monthKey] = (byMonth[monthKey] ?? 0) + 1;
          }

          final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
          final totalAttended = docs.length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xffE3F2FD),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        "$totalAttended",
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xff1565C0)),
                      ),
                      const SizedBox(height: 4),
                      const Text("إجمالي الدروس التي أعطيتها", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerRight,
                child: Text("حسب الشهر", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              const SizedBox(height: 10),
              ...months.map((monthKey) {
                final parts = monthKey.split("-");
                final year = parts[0];
                final monthIndex = int.parse(parts[1]) - 1;
                final label = "${_arabicMonths[monthIndex]} $year";

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.calendar_month, color: Color(0xff1565C0)),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xffE8F5E9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${byMonth[monthKey]} درس",
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

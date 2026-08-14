import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'teacher_schedule_screen.dart';
import 'teacher_bookings_screen.dart';
import 'teacher_requests_screen.dart';
import 'teacher_students_screen.dart';
import 'teacher_calendar_screen.dart';
import 'profile_screen.dart';
import '../services/app_language.dart';

class TeacherDashboard extends StatelessWidget {
  const TeacherDashboard({super.key});

  Widget dashboardTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required Widget destination,
    Widget? trailingBadge,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        trailing: trailingBadge ?? const Icon(Icons.chevron_left),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => destination),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xffF4F8FD),
      appBar: AppBar(
        title: Text(tr("teacher_dashboard_title")),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            dashboardTile(
              context: context,
              title: tr("my_schedule"),
              icon: Icons.calendar_month_rounded,
              color: Colors.blue,
              destination: const TeacherScheduleScreen(),
            ),
            dashboardTile(
              context: context,
              title: tr("my_calendar"),
              icon: Icons.event_available_rounded,
              color: Colors.indigo,
              destination: const TeacherCalendarScreen(),
            ),
            dashboardTile(
              context: context,
              title: tr("link_requests"),
              icon: Icons.link_rounded,
              color: Colors.orange,
              destination: const TeacherRequestsScreen(),
              trailingBadge: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("student_teacher_requests")
                    .where("teacherId", isEqualTo: teacherId)
                    .where("status", isEqualTo: "pending")
                    .snapshots(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.docs.length ?? 0;
                  if (count == 0) {
                    return const Icon(Icons.chevron_left);
                  }
                  return CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.red,
                    child: Text(
                      "$count",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
            dashboardTile(
              context: context,
              title: tr("booking_requests"),
              icon: Icons.event_note_rounded,
              color: Colors.green,
              destination: const TeacherBookingsScreen(),
            ),
            dashboardTile(
              context: context,
              title: tr("my_students"),
              icon: Icons.groups_rounded,
              color: Colors.purple,
              destination: const TeacherStudentsScreen(),
            ),
            dashboardTile(
              context: context,
              title: tr("my_profile"),
              icon: Icons.person_rounded,
              color: Colors.teal,
              destination: const ProfileScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

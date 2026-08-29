import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'student_plan_screen.dart';
import 'chat_screen.dart';
import 'student_details_screen.dart';
import 'assign_lesson_screen.dart';
import '../services/app_helpers.dart';

/// "طلابي" has 3 tabs: current active students, students who passed their
/// license, and removed students. All per-relationship data lives on the
/// student_teacher_links document, not the student's own account, since a
/// student can have more than one teacher (one per license type).
class TeacherStudentsScreen extends StatelessWidget {
  const TeacherStudentsScreen({super.key});

  Widget _tabLabel(String text, List<String> statuses) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("student_teacher_links")
          .where("teacherId", isEqualTo: teacherId)
          .where("status", whereIn: statuses)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Text("$text ($count)");
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("طلابي"),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(child: _tabLabel("الحاليين", ["active"])),
              Tab(child: _tabLabel("الناجحين", ["passed"])),
              Tab(child: _tabLabel("المحذوفين", ["removed_by_teacher", "removed_by_student"])),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ActiveStudentsTab(),
            _StatusListTab(statuses: ["passed"], emptyMessage: "لا يوجد طلاب ناجحين بعد"),
            _StatusListTab(
              statuses: ["removed_by_teacher", "removed_by_student"],
              emptyMessage: "لا يوجد طلاب محذوفين",
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab 1: current active students with the full set of quick actions.
class _ActiveStudentsTab extends StatefulWidget {
  const _ActiveStudentsTab();

  @override
  State<_ActiveStudentsTab> createState() => _ActiveStudentsTabState();
}

class _ActiveStudentsTabState extends State<_ActiveStudentsTab> {
  String searchQuery = "";

  Future<void> _setTestDate(String linkId, String studentId, String studentName) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );

    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );

    if (pickedTime == null) return;

    final dateStr = isoDate(pickedDate);
    final timeStr =
        "${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}";

    try {
      await FirebaseFirestore.instance.collection("student_teacher_links").doc(linkId).update({
        "testDate": dateStr,
        "testTime": timeStr,
      });

      final formatted = formatIsoDateTimeArabic(dateStr, timeStr);

      await sendNotification(
        userId: studentId,
        title: "تم تحديد موعد اختبارك",
        body: "تم تعيين موعد اختبار القيادة الخاص بك بتاريخ $formatted.",
        type: "test_date",
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم تحديد موعد اختبار $studentName بتاريخ $formatted")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر حفظ الموعد: $e")),
      );
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 6),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return Column(
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
            stream: FirebaseFirestore.instance
                .collection("student_teacher_links")
                .where("teacherId", isEqualTo: teacherId)
                .where("status", isEqualTo: "active")
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
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

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("لا يوجد طلاب مرتبطون بك بعد"));
              }

              final links = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: links.length,
                itemBuilder: (context, index) {
                  final link = links[index];
                  final linkData = link.data() as Map<String, dynamic>;
                  final studentId = linkData["studentId"] as String;
                  final licenseType = linkData["licenseType"] ?? "";
                  final testDate = (linkData["testDate"] ?? "").toString();
                  final testTime = (linkData["testTime"] ?? "").toString();

                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection("users").doc(studentId).get(),
                    builder: (context, studentSnap) {
                      final studentData = studentSnap.data?.data() as Map<String, dynamic>?;
                      final name = studentData?["name"] ?? "طالب";
                      final phone = studentData?["phone"] ?? "";

                      if (searchQuery.isNotEmpty) {
                        final matches = name.toString().toLowerCase().contains(searchQuery) ||
                            phone.toString().toLowerCase().contains(searchQuery);
                        if (!matches) return const SizedBox.shrink();
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xff1565C0),
                                  child: Icon(Icons.person, color: Colors.white),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text("$phone · $licenseType"),
                              ),
                              if (testDate.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 16, bottom: 6),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.event_available_rounded, size: 14, color: Colors.orange),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          "موعد الاختبار: ${formatIsoDateTimeArabic(testDate, testTime)}",
                                          style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                child: Row(
                                  children: [
                                    _actionButton(
                                      icon: Icons.flag_rounded,
                                      label: "الخطة",
                                      color: const Color(0xff1565C0),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => StudentPlanScreen(
                                              linkId: link.id,
                                              studentId: studentId,
                                              studentName: name,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    _actionButton(
                                      icon: Icons.chat_bubble_rounded,
                                      label: "محادثة",
                                      color: Colors.pink,
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              studentId: studentId,
                                              teacherId: teacherId,
                                              otherUserName: name,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    _actionButton(
                                      icon: Icons.event_available_rounded,
                                      label: "الاختبار",
                                      color: Colors.orange,
                                      onPressed: () => _setTestDate(link.id, studentId, name),
                                    ),
                                    const SizedBox(width: 6),
                                    _actionButton(
                                      icon: Icons.info_outline_rounded,
                                      label: "التفاصيل",
                                      color: Colors.teal,
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => StudentDetailsScreen(linkId: link.id),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xff1565C0)),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AssignLessonScreen(
                                            studentId: studentId,
                                            studentName: name,
                                            licenseType: licenseType,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.event_available, size: 16),
                                    label: const Text("تعيين درس لهذا الطالب", style: TextStyle(fontSize: 12.5)),
                                  ),
                                ),
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
    );
  }
}

/// Tabs 2 & 3: a searchable list of links in one or more [statuses], each
/// with a single "استرجاع" (restore) button that sets the link back to
/// active.
class _StatusListTab extends StatefulWidget {
  final List<String> statuses;
  final String emptyMessage;

  const _StatusListTab({required this.statuses, required this.emptyMessage});

  @override
  State<_StatusListTab> createState() => _StatusListTabState();
}

class _StatusListTabState extends State<_StatusListTab> {
  String searchQuery = "";

  Future<void> _restore(BuildContext context, String linkId, String studentName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("استرجاع الطالب"),
        content: Text("هل تريد استرجاع $studentName ليصبح طالبًا حاليًا لديك من جديد؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("استرجاع"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection("student_teacher_links").doc(linkId).update({
      "status": "active",
    });
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return Column(
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
            stream: FirebaseFirestore.instance
                .collection("student_teacher_links")
                .where("teacherId", isEqualTo: teacherId)
                .where("status", whereIn: widget.statuses)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      "تعذر التحميل: ${snapshot.error}",
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(child: Text(widget.emptyMessage, style: const TextStyle(color: Colors.grey)));
              }

              final links = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: links.length,
                itemBuilder: (context, index) {
                  final link = links[index];
                  final linkData = link.data() as Map<String, dynamic>;
                  final studentId = linkData["studentId"] as String;
                  final licenseType = linkData["licenseType"] ?? "";

                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection("users").doc(studentId).get(),
                    builder: (context, studentSnap) {
                      final studentData = studentSnap.data?.data() as Map<String, dynamic>?;
                      final name = studentData?["name"] ?? "طالب";
                      final phone = studentData?["phone"] ?? "";

                      if (searchQuery.isNotEmpty) {
                        final matches = name.toString().toLowerCase().contains(searchQuery) ||
                            phone.toString().toLowerCase().contains(searchQuery);
                        if (!matches) return const SizedBox.shrink();
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xff1565C0),
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("$phone · $licenseType"),
                          trailing: OutlinedButton.icon(
                            onPressed: () => _restore(context, link.id, name),
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: const Text("استرجاع", style: TextStyle(fontSize: 12)),
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
    );
  }
}

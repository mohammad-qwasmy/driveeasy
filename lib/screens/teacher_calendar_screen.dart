import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';

/// The teacher's organized schedule: defaults to the current week with all
/// 7 days shown as tabs. Tapping a day shows every booked lesson for that
/// specific day.
class TeacherCalendarScreen extends StatefulWidget {
  const TeacherCalendarScreen({super.key});

  @override
  State<TeacherCalendarScreen> createState() => _TeacherCalendarScreenState();
}

class _TeacherCalendarScreenState extends State<TeacherCalendarScreen> {
  late DateTime weekStart;
  late DateTime selectedDate;

  static const List<String> _shortWeekday = ["سبت", "أحد", "اثن", "ثلا", "أرب", "خمي", "جمع"];

  int _weekStartOffset(DateTime d) => (d.weekday + 1) % 7;

  DateTime _weekStartOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: _weekStartOffset(d)));

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    weekStart = _weekStartOf(today);
    selectedDate = DateTime(today.year, today.month, today.day);
  }

  void _changeWeek(int delta) {
    setState(() {
      weekStart = weekStart.add(Duration(days: 7 * delta));
      selectedDate = weekStart;
    });
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final thisWeekStart = _weekStartOf(today);
    final isThisWeek = isoDate(weekStart) == isoDate(thisWeekStart);

    final weekDates = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Scaffold(
      appBar: AppBar(title: const Text("جدولي"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("bookings")
            .where("teacherId", isEqualTo: teacherId)
            .where("status", isEqualTo: "approved")
            .snapshots(),
        builder: (context, snapshot) {
          final Map<String, List<QueryDocumentSnapshot>> byDate = {};
          for (final doc in snapshot.data?.docs ?? []) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data["date"] ?? "") as String;
            if (date.isEmpty) continue;
            byDate.putIfAbsent(date, () => []).add(doc);
          }

          final selectedIso = isoDate(selectedDate);
          final dayBookings = [...(byDate[selectedIso] ?? [])]
            ..sort((a, b) {
              final ta = (a.data() as Map<String, dynamic>)["time"] ?? "";
              final tb = (b.data() as Map<String, dynamic>)["time"] ?? "";
              return ta.toString().compareTo(tb.toString());
            });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeWeek(-1),
                    ),
                    Text(
                      isThisWeek
                          ? "هذا الأسبوع"
                          : "${weekDates.first.day}/${weekDates.first.month} - ${weekDates.last.day}/${weekDates.last.month}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1565C0)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeWeek(1),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 72,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: 7,
                  itemBuilder: (context, i) {
                    final date = weekDates[i];
                    final iso = isoDate(date);
                    final isSelected = iso == selectedIso;
                    final isToday = date.isAtSameMomentAs(todayOnly);
                    final hasBookings = (byDate[iso]?.isNotEmpty ?? false);

                    return GestureDetector(
                      onTap: () => setState(() => selectedDate = date),
                      child: Container(
                        width: 52,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xff1565C0)
                              : isToday
                                  ? const Color(0xffE3F2FD)
                                  : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _shortWeekday[i],
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected ? Colors.white70 : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "${date.day}",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (hasBookings)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.white : const Color(0xff1565C0),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatIsoDateArabic(selectedIso),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: dayBookings.isEmpty
                    ? const Center(child: Text("لا يوجد دروس محجوزة في هذا اليوم", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: dayBookings.length,
                        itemBuilder: (context, index) {
                          final doc = dayBookings[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final isPastOrToday = selectedIso.compareTo(isoDate(todayOnly)) <= 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FutureBuilder<DocumentSnapshot>(
                                          future: FirebaseFirestore.instance
                                              .collection("users")
                                              .doc(data["studentId"])
                                              .get(),
                                          builder: (context, studentSnap) {
                                            final studentData =
                                                studentSnap.data?.data() as Map<String, dynamic>?;
                                            final studentName = studentData?["name"] ?? "طالب";

                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                const SizedBox(height: 3),
                                                Text(
                                                  "${data["time"]} · ${data["price"]} ₪",
                                                  style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      if (isPastOrToday)
                                        _AttendanceButton(bookingId: doc.id, attendance: data["attendance"]),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (data["cancelRequested"] == true)
                                    _CancelRequestBanner(
                                      bookingId: doc.id,
                                      studentId: data["studentId"] ?? "",
                                      dateStr: data["date"] ?? "",
                                      time: data["time"] ?? "",
                                      slotId: data["slotId"] ?? "",
                                    )
                                  else
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () => _teacherCancelLesson(
                                          context,
                                          bookingId: doc.id,
                                          studentId: data["studentId"] ?? "",
                                          slotId: data["slotId"] ?? "",
                                          dateStr: data["date"] ?? "",
                                          time: data["time"] ?? "",
                                        ),
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        icon: const Icon(Icons.delete_outline, size: 16),
                                        label: const Text("حذف الدرس", style: TextStyle(fontSize: 12)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The teacher cancelling a lesson directly (no approval needed — it's
/// their own action). Frees the slot and notifies the student immediately.
Future<void> _teacherCancelLesson(
  BuildContext context, {
  required String bookingId,
  required String studentId,
  required String slotId,
  required String dateStr,
  required String time,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("حذف الدرس"),
      content: const Text("هل أنت متأكد من إلغاء هذا الدرس؟ سيتم إشعار الطالب فورًا."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("تراجع")),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text("إلغاء الدرس"),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  final firestore = FirebaseFirestore.instance;
  await firestore.collection("bookings").doc(bookingId).update({"status": "rejected"});
  if (slotId.isNotEmpty) {
    await firestore.collection("teacher_slots").doc(slotId).update({"status": "available"});
  }

  await sendNotification(
    userId: studentId,
    title: "تم إلغاء الدرس",
    body: "تم إلغاء درسك يوم ${dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : ''} الساعة $time من قبل المدرب.",
    type: "lesson_cancelled",
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("تم إلغاء الدرس")),
  );
}

/// Shown on a lesson the student has asked to cancel — the teacher must
/// approve or reject the request.
class _CancelRequestBanner extends StatelessWidget {
  final String bookingId;
  final String studentId;
  final String dateStr;
  final String time;
  final String slotId;

  const _CancelRequestBanner({
    required this.bookingId,
    required this.studentId,
    required this.dateStr,
    required this.time,
    required this.slotId,
  });

  Future<void> _approve(BuildContext context) async {
    final firestore = FirebaseFirestore.instance;
    await firestore.collection("bookings").doc(bookingId).update({"status": "rejected"});
    if (slotId.isNotEmpty) {
      await firestore.collection("teacher_slots").doc(slotId).update({"status": "available"});
    }

    await sendNotification(
      userId: studentId,
      title: "تم إلغاء الدرس",
      body: "تمت الموافقة على إلغاء درسك يوم ${dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : ''} الساعة $time.",
      type: "lesson_cancelled",
    );
  }

  Future<void> _reject(BuildContext context) async {
    await FirebaseFirestore.instance.collection("bookings").doc(bookingId).update({
      "cancelRequested": false,
    });

    await sendNotification(
      userId: studentId,
      title: "تم رفض طلب الإلغاء",
      body: "لم يوافق المدرب على إلغاء درسك يوم ${dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : ''} الساعة $time، الدرس ما زال قائمًا.",
      type: "cancel_rejected",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "الطالب يريد إلغاء هذا الدرس",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => _approve(context),
                  child: const Text("موافقة على الإلغاء", style: TextStyle(fontSize: 11.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => _reject(context),
                  child: const Text("رفض الطلب", style: TextStyle(fontSize: 11.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttendanceButton extends StatelessWidget {
  final String bookingId;
  final String? attendance;

  const _AttendanceButton({required this.bookingId, required this.attendance});

  Future<void> _setAttendance(String value) async {
    await FirebaseFirestore.instance.collection("bookings").doc(bookingId).update({"attendance": value});
  }

  @override
  Widget build(BuildContext context) {
    if (attendance == "attended") {
      return Chip(
        label: const Text("حضر", style: TextStyle(color: Colors.white, fontSize: 12)),
        backgroundColor: Colors.green,
        avatar: const Icon(Icons.check, color: Colors.white, size: 16),
      );
    }

    if (attendance == "absent") {
      return Chip(
        label: const Text("لم يحضر", style: TextStyle(color: Colors.white, fontSize: 12)),
        backgroundColor: Colors.red,
        avatar: const Icon(Icons.close, color: Colors.white, size: 16),
      );
    }

    return PopupMenuButton<String>(
      onSelected: _setAttendance,
      itemBuilder: (context) => const [
        PopupMenuItem(value: "attended", child: Text("حضر")),
        PopupMenuItem(value: "absent", child: Text("لم يحضر")),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: const Text(
          "تسجيل الحضور",
          style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

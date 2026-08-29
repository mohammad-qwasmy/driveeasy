import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';
import '../widgets/month_calendar.dart';

/// Calendar-based schedule setup: the teacher taps a specific date on a
/// full month view and sets up (or edits) that single day's availability —
/// no recurring weeks. Supports two tiers of breaks: a short break after
/// every few lessons, and a longer break after a certain number of short
/// breaks.
class TeacherScheduleScreen extends StatefulWidget {
  const TeacherScheduleScreen({super.key});

  @override
  State<TeacherScheduleScreen> createState() => _TeacherScheduleScreenState();
}

class _TeacherScheduleScreenState extends State<TeacherScheduleScreen> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  DateTime? selectedDate;

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("إعداد أوقات العمل"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection("teacher_slots")
            .where("teacherId", isEqualTo: teacherId)
            .snapshots(),
        builder: (context, snapshot) {
          final markedDates = <String>{};
          if (snapshot.hasData) {
            for (final doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final date = data["date"];
              if (date != null) markedDates.add(date);
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "اختر يوماً من الشهر لإعداد أو تعديل جدول عملك فيه. النقاط الزرقاء تشير لأيام لديها جدول مسبق.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: MonthCalendar(
                      selectedDate: selectedDate,
                      markedDates: markedDates,
                      disablePastDates: true,
                      onDaySelected: (date) => setState(() => selectedDate = date),
                    ),
                  ),
                ),
                if (selectedDate != null) ...[
                  const SizedBox(height: 18),
                  _DayScheduleEditor(
                    key: ValueKey(isoDate(selectedDate!)),
                    date: selectedDate!,
                    teacherId: teacherId,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DayScheduleEditor extends StatefulWidget {
  final DateTime date;
  final String teacherId;

  const _DayScheduleEditor({super.key, required this.date, required this.teacherId});

  @override
  State<_DayScheduleEditor> createState() => _DayScheduleEditorState();
}

class _DayScheduleEditorState extends State<_DayScheduleEditor> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final TextEditingController startTime = TextEditingController(text: "08:00");
  final TextEditingController endTime = TextEditingController(text: "16:00");
  final TextEditingController lessonPrice = TextEditingController();

  String lessonDuration = "40";
  String shortBreakDuration = "10";
  String shortBreakAfter = "1";
  String longBreakDuration = "30";
  String longBreakAfter = "0"; // 0 = disabled

  bool isSaving = false;

  final List<String> durations = ["30", "40", "45", "60", "80", "90", "120"];
  final List<String> breakDurations = ["0", "5", "10", "15", "20", "30", "45", "60"];
  final List<String> counts = ["0", "1", "2", "3", "4", "5", "6"];

  TimeOfDay _stringToTime(String time) {
    final parts = time.split(":");
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _timeToString(TimeOfDay time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  TimeOfDay _addMinutes(TimeOfDay time, int minutes) {
    int total = time.hour * 60 + time.minute + minutes;
    return TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
  }

  bool _isAfter(TimeOfDay a, TimeOfDay b) =>
      a.hour > b.hour || (a.hour == b.hour && a.minute > b.minute);

  Future<void> _save() async {
    if (startTime.text.isEmpty || endTime.text.isEmpty || lessonPrice.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى تعبئة جميع الحقول")),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final dateStr = isoDate(widget.date);

      // Remove this day's previous *available* slots before regenerating,
      // so re-saving a day never creates duplicates. Booked/pending slots
      // (already reserved by students) are left untouched.
      final existing = await firestore
          .collection("teacher_slots")
          .where("teacherId", isEqualTo: widget.teacherId)
          .where("date", isEqualTo: dateStr)
          .where("status", isEqualTo: "available")
          .get();

      for (final doc in existing.docs) {
        await doc.reference.delete();
      }

      TimeOfDay current = _stringToTime(startTime.text);
      final TimeOfDay finish = _stringToTime(endTime.text);

      final lessonMinutes = int.parse(lessonDuration);
      final shortBreakMinutes = int.parse(shortBreakDuration);
      final shortAfter = int.parse(shortBreakAfter);
      final longBreakMinutes = int.parse(longBreakDuration);
      final longAfter = int.parse(longBreakAfter);

      int lessonCount = 0;
      int shortBreakCount = 0;
      int created = 0;

      final batch = firestore.batch();

      while (!_isAfter(current, finish) &&
          !_isAfter(_addMinutes(current, lessonMinutes), finish)) {
        final lessonEnd = _addMinutes(current, lessonMinutes);

        final ref = firestore.collection("teacher_slots").doc();
        batch.set(ref, {
          "teacherId": widget.teacherId,
          "day": weekdayNameFromDate(widget.date),
          "date": dateStr,
          "startTime": _timeToString(current),
          "endTime": _timeToString(lessonEnd),
          "price": lessonPrice.text.trim(),
          "status": "available",
          "createdAt": Timestamp.now(),
        });
        created++;

        lessonCount++;
        current = lessonEnd;

        if (shortAfter > 0 && lessonCount % shortAfter == 0) {
          shortBreakCount++;
          if (longAfter > 0 && shortBreakCount % longAfter == 0) {
            current = _addMinutes(current, longBreakMinutes);
          } else if (shortBreakMinutes > 0) {
            current = _addMinutes(current, shortBreakMinutes);
          }
        }
      }

      if (created == 0) {
        if (!mounted) return;
        setState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("لم يتم إنشاء أي موعد — تأكد أن وقت النهاية بعد وقت البداية بما يكفي لدرس واحد على الأقل")),
        );
        return;
      }

      await batch.commit();

      if (!mounted) return;
      setState(() => isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم حفظ جدول اليوم بنجاح — $created موعد")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر الحفظ: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = isoDate(widget.date);

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatIsoDateArabic(dateStr),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff1565C0)),
            ),
            const SizedBox(height: 14),

            const Text("موجود لهذا اليوم", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("teacher_slots")
                  .where("teacherId", isEqualTo: widget.teacherId)
                  .where("date", isEqualTo: dateStr)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Text("لا يوجد جدول محفوظ بعد لهذا اليوم", style: TextStyle(color: Colors.grey, fontSize: 12.5));
                }
                final sorted = [...docs]..sort((a, b) {
                  final ta = (a.data() as Map<String, dynamic>)["startTime"] ?? "";
                  final tb = (b.data() as Map<String, dynamic>)["startTime"] ?? "";
                  return ta.toString().compareTo(tb.toString());
                });
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: sorted.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final booked = d["status"] != "available";
                    return Chip(
                      label: Text("${d["startTime"]}-${d["endTime"]}", style: const TextStyle(fontSize: 11.5)),
                      backgroundColor: booked ? Colors.orange.shade50 : Colors.blue.shade50,
                      avatar: Icon(booked ? Icons.lock : Icons.event_available, size: 14),
                      deleteIcon: booked ? null : const Icon(Icons.close, size: 14),
                      onDeleted: booked
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text("حذف الموعد"),
                                  content: Text("هل تريد حذف موعد ${d["startTime"]}-${d["endTime"]}؟"),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text("حذف", style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await doc.reference.delete();
                              }
                            },
                    );
                  }).toList(),
                );
              },
            ),

            const Divider(height: 30),

            const Text("إعداد جدول هذا اليوم", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startTime,
                    decoration: const InputDecoration(labelText: "وقت البداية", border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: endTime,
                    decoration: const InputDecoration(labelText: "وقت النهاية", border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: lessonDuration,
              decoration: const InputDecoration(labelText: "مدة الدرس (دقيقة)", border: OutlineInputBorder(), isDense: true),
              items: durations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (v) => setState(() => lessonDuration = v!),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: lessonPrice,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "سعر الدرس", border: OutlineInputBorder(), isDense: true),
            ),

            const SizedBox(height: 18),
            const Text("الاستراحة القصيرة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: shortBreakDuration,
                    decoration: const InputDecoration(labelText: "المدة (دقيقة)", border: OutlineInputBorder(), isDense: true),
                    items: breakDurations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (v) => setState(() => shortBreakDuration = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: shortBreakAfter,
                    decoration: const InputDecoration(labelText: "بعد كل كم درس", border: OutlineInputBorder(), isDense: true),
                    items: counts.map((d) => DropdownMenuItem(value: d, child: Text(d == "0" ? "بدون" : d))).toList(),
                    onChanged: (v) => setState(() => shortBreakAfter = v!),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            const Text("الاستراحة الطويلة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: longBreakDuration,
                    decoration: const InputDecoration(labelText: "المدة (دقيقة)", border: OutlineInputBorder(), isDense: true),
                    items: breakDurations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (v) => setState(() => longBreakDuration = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: longBreakAfter,
                    decoration: const InputDecoration(labelText: "بعد كم استراحة قصيرة", border: OutlineInputBorder(), isDense: true),
                    items: counts.map((d) => DropdownMenuItem(value: d, child: Text(d == "0" ? "بدون" : d))).toList(),
                    onChanged: (v) => setState(() => longBreakAfter = v!),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isSaving ? null : _save,
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text("حفظ جدول هذا اليوم"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

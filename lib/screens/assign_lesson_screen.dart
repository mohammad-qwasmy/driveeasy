import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';
import '../widgets/month_calendar.dart';

/// Lets a teacher propose one or more lesson slots to a single student at
/// once, instead of waiting for the student to book. The student gets a
/// separate notification for each lesson and sees each one on their own
/// "مواعيدي" screen, where they accept or reject them individually.
///
/// If [studentId] is provided, that student is fixed (opened from their
/// card in "طلابي"). Otherwise the teacher first picks one of their active
/// students — used when reassigning a lesson a student rejected to
/// someone else.
class AssignLessonScreen extends StatefulWidget {
  final String? studentId;
  final String? studentName;
  final String? licenseType;

  const AssignLessonScreen({super.key, this.studentId, this.studentName, this.licenseType});

  @override
  State<AssignLessonScreen> createState() => _AssignLessonScreenState();
}

class _AssignLessonScreenState extends State<AssignLessonScreen> {
  bool isSubmitting = false;
  DateTime? selectedDate;
  // A slot's id being a key here is what marks it "selected" — each
  // selected slot keeps its own note controller so every lesson can carry
  // a different note to the student.
  final Map<String, TextEditingController> selectedSlotNotes = {};

  // Only used when no student was pre-selected.
  String? pickedStudentId;
  String? pickedStudentName;
  String? pickedLicenseType;

  String? get _studentId => widget.studentId ?? pickedStudentId;
  String? get _studentName => widget.studentName ?? pickedStudentName;
  String? get _licenseType => widget.licenseType ?? pickedLicenseType;

  @override
  void dispose() {
    for (final controller in selectedSlotNotes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Assigns every selected slot to the same student, one Firestore
  /// transaction per slot so two lessons can never clash with each other
  /// or with a slot someone else just took. Slots that got taken in the
  /// meantime are reported back instead of silently failing — the rest
  /// still go through.
  Future<void> _assign() async {
    if (selectedSlotNotes.isEmpty) return;
    final studentId = _studentId;
    final studentName = _studentName;
    final licenseType = _licenseType ?? "";
    if (studentId == null || studentName == null) return;

    final teacher = FirebaseAuth.instance.currentUser;
    if (teacher == null) return;

    setState(() => isSubmitting = true);

    final firestore = FirebaseFirestore.instance;
    final teacherDoc = await firestore.collection("users").doc(teacher.uid).get();
    final teacherName = (teacherDoc.data() as Map<String, dynamic>?)?["name"] ?? "المدرب";

    int succeeded = 0;
    final failedMessages = <String>[];

    for (final entry in selectedSlotNotes.entries) {
      final slotId = entry.key;
      final note = entry.value.text.trim();
      final slotRef = firestore.collection("teacher_slots").doc(slotId);
      final bookingRef = firestore.collection("bookings").doc();

      try {
        late Map<String, dynamic> slotData;
        await firestore.runTransaction((transaction) async {
          final slotSnap = await transaction.get(slotRef);
          if (!slotSnap.exists) {
            throw Exception("موعد لم يعد موجوداً");
          }
          slotData = slotSnap.data() as Map<String, dynamic>;
          if (slotData["status"] != "available") {
            throw Exception("موعد ${slotData["startTime"]} لم يعد متاحاً");
          }

          transaction.update(slotRef, {"status": "pending"});

          transaction.set(bookingRef, {
            "studentId": studentId,
            "teacherId": teacher.uid,
            "teacherName": teacherName,
            "licenseType": licenseType,
            "day": slotData["day"] ?? "",
            "date": slotData["date"] ?? "",
            "time": "${slotData["startTime"]} - ${slotData["endTime"]}",
            "price": slotData["price"].toString(),
            "slotId": slotId,
            "status": "teacherProposed",
            "teacherInitiated": true,
            "teacherNote": note,
            "attendance": null,
            "createdAt": Timestamp.now(),
          });
        });

        succeeded++;

        final dateText = slotData["date"] != null && slotData["date"].toString().isNotEmpty
            ? formatIsoDateArabic(slotData["date"])
            : slotData["day"];
        await sendNotification(
          userId: studentId,
          title: "درس مقترح من المدرب",
          body: note.isEmpty
              ? "اقترح عليك $teacherName درساً يوم $dateText الساعة ${slotData["startTime"]}، بانتظار موافقتك."
              : "اقترح عليك $teacherName درساً يوم $dateText الساعة ${slotData["startTime"]}. ملاحظة المدرب: $note",
          type: "teacher_proposed_lesson",
        );
      } catch (e) {
        failedMessages.add(e.toString().replaceAll("Exception: ", ""));
      }
    }

    if (!mounted) return;
    for (final controller in selectedSlotNotes.values) {
      controller.dispose();
    }
    setState(() {
      isSubmitting = false;
      selectedSlotNotes.clear();
    });

    if (failedMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            succeeded == 1
                ? "تم إرسال اقتراح الدرس إلى $studentName"
                : "تم إرسال $succeeded اقتراحات دروس إلى $studentName",
          ),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم إرسال $succeeded، وتعذر: ${failedMessages.join('، ')}")),
      );
    }
  }

  Widget _studentPicker() {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("student_teacher_links")
          .where("teacherId", isEqualTo: teacherId)
          .where("status", isEqualTo: "active")
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final links = snapshot.data?.docs ?? [];
        if (links.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text("لا يوجد طلاب حاليون مرتبطون بك بعد"),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: links.length,
          itemBuilder: (context, index) {
            final link = links[index];
            final data = link.data() as Map<String, dynamic>;
            final studentId = data["studentId"] as String;
            final licenseType = data["licenseType"] ?? "";
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection("users").doc(studentId).get(),
              builder: (context, studentSnap) {
                final name = (studentSnap.data?.data() as Map<String, dynamic>?)?["name"] ?? "طالب";
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name),
                    subtitle: Text(licenseType),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => setState(() {
                      pickedStudentId = studentId;
                      pickedStudentName = name;
                      pickedLicenseType = licenseType;
                    }),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _slotPicker() {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.person)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _studentName ?? "",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  if (widget.studentId == null)
                    TextButton(
                      onPressed: () => setState(() {
                        pickedStudentId = null;
                        pickedStudentName = null;
                        pickedLicenseType = null;
                        selectedDate = null;
                        for (final controller in selectedSlotNotes.values) {
                          controller.dispose();
                        }
                        selectedSlotNotes.clear();
                      }),
                      child: const Text("تغيير"),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "اختر يوماً من الشهر لعرض أوقاتك المتاحة فيه",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("teacher_slots")
                    .where("teacherId", isEqualTo: teacherId)
                    .where("status", isEqualTo: "available")
                    .snapshots(),
                builder: (context, snapshot) {
                  final markedDates = <String>{};
                  if (snapshot.hasData) {
                    for (final doc in snapshot.data!.docs) {
                      final d = doc.data() as Map<String, dynamic>;
                      final date = d["date"];
                      final startTime = (d["startTime"] ?? "").toString();
                      if (date != null && !isSlotPast(date, startTime)) {
                        markedDates.add(date);
                      }
                    }
                  }
                  return MonthCalendar(
                    selectedDate: selectedDate,
                    markedDates: markedDates,
                    disablePastDates: true,
                    onDaySelected: (date) => setState(() {
                      selectedDate = date;
                      for (final controller in selectedSlotNotes.values) {
                        controller.dispose();
                      }
                      selectedSlotNotes.clear();
                    }),
                  );
                },
              ),
            ),
          ),
          if (selectedDate != null) ...[
            const SizedBox(height: 18),
            Text(
              "أوقاتك المتاحة يوم ${formatIsoDateArabic(isoDate(selectedDate!))} (يمكنك اختيار أكثر من موعد لنفس الطالب)",
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("teacher_slots")
                  .where("teacherId", isEqualTo: teacherId)
                  .where("status", isEqualTo: "available")
                  .where("date", isEqualTo: isoDate(selectedDate!))
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final slots = [...(snapshot.data?.docs ?? [])]
                    .where((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      return !isSlotPast((d["date"] ?? "").toString(), (d["startTime"] ?? "").toString());
                    })
                    .toList()
                  ..sort((a, b) {
                    final ta = (a.data() as Map<String, dynamic>)["startTime"] ?? "";
                    final tb = (b.data() as Map<String, dynamic>)["startTime"] ?? "";
                    return ta.toString().compareTo(tb.toString());
                  });

                if (slots.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text("لا يوجد أوقات متاحة في هذا اليوم"),
                  );
                }

                return Column(
                  children: slots.map((item) {
                    final data = item.data() as Map<String, dynamic>;
                    final selected = selectedSlotNotes.containsKey(item.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: selected ? const Color(0xff1565C0) : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            value: selected,
                            onChanged: (_) => setState(() {
                              if (selected) {
                                selectedSlotNotes.remove(item.id)?.dispose();
                              } else {
                                selectedSlotNotes[item.id] = TextEditingController();
                              }
                            }),
                            secondary: Icon(
                              Icons.access_time,
                              color: selected ? const Color(0xff1565C0) : Colors.grey,
                            ),
                            title: Text("${data["startTime"]} - ${data["endTime"]}"),
                            subtitle: Text("${data["price"]} ₪"),
                          ),
                          if (selected)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: TextField(
                                controller: selectedSlotNotes[item.id],
                                maxLines: 2,
                                decoration: InputDecoration(
                                  hintText: "ملاحظة لهذا الدرس (اختياري)",
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: (selectedSlotNotes.isEmpty || isSubmitting) ? null : _assign,
              child: isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      selectedSlotNotes.length > 1
                          ? "إرسال ${selectedSlotNotes.length} اقتراحات دروس"
                          : "إرسال اقتراح الدرس",
                      style: const TextStyle(fontSize: 18),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsStudentPick = widget.studentId == null && _studentId == null;
    return Scaffold(
      appBar: AppBar(title: const Text("تعيين درس لطالب"), centerTitle: true),
      body: needsStudentPick ? _studentPicker() : _slotPicker(),
    );
  }
}

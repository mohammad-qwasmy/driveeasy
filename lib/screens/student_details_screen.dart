import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'student_plan_screen.dart';
import 'chat_screen.dart';
import '../services/app_helpers.dart';

/// Profile page a teacher opens to see full details of one specific
/// student↔teacher relationship (a student may have more than one teacher —
/// one per license type — so everything here is scoped to this one link,
/// not the student's whole account).
class StudentDetailsScreen extends StatefulWidget {
  final String linkId;

  const StudentDetailsScreen({super.key, required this.linkId});

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  final requiredLessonsController = TextEditingController();
  bool isSaving = false;
  bool _requiredLessonsInitialized = false;

  Widget infoTile(IconData icon, String title, String value) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xff1565C0)),
      title: Text(title),
      subtitle: Text(value.isEmpty ? "غير متوفر" : value),
    );
  }

  Future<String> _teacherSchoolName(String teacherId) async {
    final teacherDoc = await FirebaseFirestore.instance.collection("users").doc(teacherId).get();
    final schoolId = (teacherDoc.data() as Map<String, dynamic>?)?["schoolId"] ?? "";
    if (schoolId.toString().isEmpty) return "";

    final schoolDoc = await FirebaseFirestore.instance.collection("schools").doc(schoolId).get();
    return (schoolDoc.data() as Map<String, dynamic>?)?["name"] ?? "";
  }

  Future<void> _saveRequiredLessons() async {
    final value = int.tryParse(requiredLessonsController.text.trim());
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("أدخل رقماً صحيحاً")),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection("student_teacher_links")
          .doc(widget.linkId)
          .update({"requiredLessons": value});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم تحديث عدد الدروس المطلوبة")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر الحفظ: $e")),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _testDateMenu(String studentId, String studentName, bool hasTestDate) async {
    if (!hasTestDate) {
      await _setTestDate(studentId, studentName);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("موعد الاختبار"),
        content: const Text("ماذا تريد أن تفعل بموعد الاختبار؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إغلاق")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, "cancel"),
            child: const Text("إلغاء الموعد", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, "edit"),
            child: const Text("تعديل الموعد"),
          ),
        ],
      ),
    );

    if (choice == "edit") {
      await _setTestDate(studentId, studentName);
    } else if (choice == "cancel") {
      await _cancelTestDate(studentId, studentName);
    }
  }

  Future<void> _cancelTestDate(String studentId, String studentName) async {
    await FirebaseFirestore.instance.collection("student_teacher_links").doc(widget.linkId).update({
      "testDate": "",
      "testTime": "",
    });

    await sendNotification(
      userId: studentId,
      title: "تم إلغاء موعد الاختبار",
      body: "تم إلغاء موعد اختبار القيادة الخاص بك.",
      type: "test_date_cancelled",
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("تم إلغاء موعد اختبار $studentName")),
    );
  }

  Future<void> _setTestDate(String studentId, String studentName) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );

    if (picked == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );

    if (pickedTime == null) return;

    final dateStr = isoDate(picked);
    final timeStr =
        "${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}";

    try {
      await FirebaseFirestore.instance.collection("student_teacher_links").doc(widget.linkId).update({
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

  Future<void> _markResult(String studentId, String studentName, String licenseType, String result) async {
    final isPass = result == "passed";
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isPass ? "تأكيد النجاح" : "تأكيد التخطي"),
        content: Text(
          isPass
              ? "هل أنت متأكد أن $studentName نجح باختبار رخصة $licenseType؟ لن يتمكن من حجز دروس جديدة لهذه الرخصة بعد ذلك."
              : "هل أنت متأكد من تخطي رخصة $licenseType لـ $studentName؟",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: isPass ? Colors.green : Colors.orange),
            child: const Text("تأكيد"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection("student_teacher_links").doc(widget.linkId).update({
      "status": result,
    });

    if (isPass) {
      await sendNotification(
        userId: studentId,
        title: "مبروك النجاح!",
        body: "مبروك، تم النجاح برخصة $licenseType 🎉",
        type: "license_passed",
      );
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _deleteStudent(String studentName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف الطالب"),
        content: Text(
          "هل أنت متأكد من حذف $studentName من قائمة طلابك؟ ستبقى بياناته وسجل دروسه محفوظة، ويمكنه الارتباط بمدرب آخر لنفس نوع الرخصة.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection("student_teacher_links").doc(widget.linkId).update({
      "status": "removed_by_teacher",
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _printDetails({
    required String studentName,
    required String phone,
    required String licenseType,
    required int attendedCount,
    required int requiredLessons,
  }) async {
    final steps = await ensureStudentPlan(widget.linkId);
    final done = steps.where((s) => s["done"] == true).length;
    final schoolName = await _teacherSchoolName(FirebaseAuth.instance.currentUser!.uid);

    final font = await PdfGoogleFonts.notoNaskhArabicRegular();
    final boldFont = await PdfGoogleFonts.notoNaskhArabicBold();
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("تقرير الطالب", style: pw.TextStyle(fontSize: 22, font: boldFont)),
            pw.SizedBox(height: 16),
            if (schoolName.isNotEmpty) ...[
              pw.Text("المدرسة: $schoolName", style: pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 6),
            ],
            pw.Text("الاسم: $studentName", style: pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 6),
            pw.Text("رقم الهاتف: $phone", style: pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 6),
            pw.Text("نوع الرخصة: $licenseType", style: pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text("عدد الدروس التي أخذها: $attendedCount", style: pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 6),
            pw.Text(
              "العدد الإجمالي المطلوب: ${requiredLessons > 0 ? requiredLessons.toString() : "غير محدد"}",
              style: pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text("خطة التعلم: $done من ${steps.length} منجز", style: pw.TextStyle(fontSize: 14, font: boldFont)),
            pw.SizedBox(height: 10),
            ...steps.map((s) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    "${s["done"] == true ? "✔" : "○"}  ${s["title"]}",
                    style: pw.TextStyle(fontSize: 12),
                  ),
                )),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("معلومات الطالب"), centerTitle: true),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("student_teacher_links")
            .doc(widget.linkId)
            .snapshots(),
        builder: (context, linkSnap) {
          if (linkSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text("تعذر تحميل بيانات الارتباط:\n${linkSnap.error}",
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ),
            );
          }

          if (!linkSnap.hasData || !linkSnap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final linkData = linkSnap.data!.data() as Map<String, dynamic>;
          final studentId = linkData["studentId"] as String;
          final licenseType = linkData["licenseType"] ?? "";
          final requiredLessons = linkData["requiredLessons"] ?? 0;
          final testDate = (linkData["testDate"] ?? "").toString();
          final testTime = (linkData["testTime"] ?? "").toString();

          if (!_requiredLessonsInitialized) {
            _requiredLessonsInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                requiredLessonsController.text = requiredLessons.toString();
              }
            });
          }

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection("users").doc(studentId).get(),
            builder: (context, studentSnap) {
              if (!studentSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final studentData = studentSnap.data!.data() as Map<String, dynamic>? ?? {};
              final name = studentData["name"] ?? "";
              final email = studentData["email"] ?? "";
              final phone = studentData["phone"] ?? "";
              final city = studentData["city"] ?? "";

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 50,
                      backgroundColor: Color(0xff1565C0),
                      child: Icon(Icons.person, size: 55, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("طالب - رخصة $licenseType", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StudentPlanScreen(
                                    linkId: widget.linkId,
                                    studentId: studentId,
                                    studentName: name,
                                  ),
                                ),
                              );
                            },
                            child: const Column(
                              children: [
                                Icon(Icons.flag_rounded, size: 20),
                                SizedBox(height: 4),
                                Text("الخطة", style: TextStyle(fontSize: 11.5)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
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
                            child: const Column(
                              children: [
                                Icon(Icons.chat_bubble_rounded, size: 20),
                                SizedBox(height: 4),
                                Text("محادثة", style: TextStyle(fontSize: 11.5)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.orange),
                              foregroundColor: Colors.orange,
                            ),
                            onPressed: () => _testDateMenu(studentId, name, testDate.isNotEmpty),
                            child: const Column(
                              children: [
                                Icon(Icons.event_available_rounded, size: 20),
                                SizedBox(height: 4),
                                Text("الاختبار", style: TextStyle(fontSize: 11.5)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          FutureBuilder<String>(
                            future: _teacherSchoolName(teacherId),
                            builder: (context, schoolSnap) {
                              return infoTile(Icons.school, "المدرسة", schoolSnap.data ?? "");
                            },
                          ),
                          const Divider(height: 1),
                          infoTile(Icons.email, "البريد الإلكتروني", email),
                          const Divider(height: 1),
                          infoTile(Icons.phone, "رقم الهاتف", phone),
                          const Divider(height: 1),
                          infoTile(Icons.location_city, "المدينة", city),
                          const Divider(height: 1),
                          infoTile(
                            Icons.event_available_rounded,
                            "موعد الاختبار",
                            testDate.isNotEmpty ? formatIsoDateTimeArabic(testDate, testTime) : "",
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "العدد الإجمالي للدروس المطلوبة لإنهاء الدورة",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: requiredLessonsController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isSaving ? null : _saveRequiredLessons,
                                child: isSaving
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text("حفظ"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "الحجوزات مع هذا الطالب",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                      ),
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("bookings")
                          .where("studentId", isEqualTo: studentId)
                          .where("teacherId", isEqualTo: teacherId)
                          .snapshots(),
                      builder: (context, bookingSnapshot) {
                        if (bookingSnapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              "تعذر تحميل الحجوزات: ${bookingSnapshot.error}",
                              style: const TextStyle(color: Colors.red, fontSize: 12.5),
                            ),
                          );
                        }

                        if (!bookingSnapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: CircularProgressIndicator(),
                          );
                        }

                        final allBookings = bookingSnapshot.data!.docs;
                        final attendedCount = allBookings
                            .where((d) => (d.data() as Map<String, dynamic>)["attendance"] == "attended")
                            .length;

                        // Only show bookings that are still upcoming and not
                        // cancelled — a cancelled lesson or one whose time
                        // has already passed shouldn't clutter this list.
                        final bookings = allBookings.where((doc) {
                          final b = doc.data() as Map<String, dynamic>;
                          if (b["status"] == "rejected") return false;
                          final date = (b["date"] ?? "").toString();
                          final time = (b["time"] ?? "").toString();
                          if (date.isEmpty) return true;
                          return !isBookingPast(date, time);
                        }).toList()
                          ..sort((a, b) {
                            final da = (a.data() as Map<String, dynamic>)["date"] ?? "";
                            final db = (b.data() as Map<String, dynamic>)["date"] ?? "";
                            final cmp = da.toString().compareTo(db.toString());
                            if (cmp != 0) return cmp;
                            final ta = (a.data() as Map<String, dynamic>)["time"] ?? "";
                            final tb = (b.data() as Map<String, dynamic>)["time"] ?? "";
                            return ta.toString().compareTo(tb.toString());
                          });

                        return Column(
                          children: [
                            if (allBookings.isNotEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    "دروس حضرها: $attendedCount",
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            if (bookings.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Text("لا يوجد حجوزات قادمة", style: TextStyle(color: Colors.grey)),
                              ),
                            ...bookings.map((doc) {
                              final b = doc.data() as Map<String, dynamic>;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: const Icon(Icons.calendar_month, color: Color(0xff1565C0)),
                                  title: Text(
                                    (b["date"] ?? "").toString().isNotEmpty
                                        ? formatIsoDateArabic(b["date"])
                                        : "${b["day"]}",
                                  ),
                                  subtitle: Text("${b["time"]} · ${b["price"]} ₪"),
                                  trailing: Text(
                                    b["status"] == "approved" ? "مقبول" : "قيد الانتظار",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: b["status"] == "approved" ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _printDetails(
                                  studentName: name,
                                  phone: phone,
                                  licenseType: licenseType,
                                  attendedCount: attendedCount,
                                  requiredLessons: requiredLessons,
                                ),
                                icon: const Icon(Icons.print_rounded),
                                label: const Text("طباعة تفاصيل الطالب"),
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: () => _markResult(studentId, name, licenseType, "passed"),
                        icon: const Icon(Icons.emoji_events_rounded, color: Colors.white),
                        label: const Text("نجح بالرخصة", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: () => _deleteStudent(name),
                        icon: const Icon(Icons.person_remove_rounded),
                        label: const Text("حذف الطالب"),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

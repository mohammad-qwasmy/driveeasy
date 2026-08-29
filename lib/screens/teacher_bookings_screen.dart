import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';
import '../widgets/count_label.dart';
import 'assign_lesson_screen.dart';

/// Three tabs: new booking requests (status pending), cancellation
/// requests (a student asking to cancel an already-approved lesson), and
/// lessons the teacher proposed directly (awaiting the student's response,
/// or rejected and needing the teacher to resend/reassign).
/// Approving/rejecting either removes it from this screen appropriately.
class TeacherBookingsScreen extends StatelessWidget {
  const TeacherBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("طلبات الحجز"),
          centerTitle: true,
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(
                child: CountLabel(
                  text: "طلبات الحجز",
                  stream: FirebaseFirestore.instance
                      .collection("bookings")
                      .where("teacherId", isEqualTo: teacherId)
                      .where("status", isEqualTo: "pending")
                      .snapshots(),
                ),
              ),
              Tab(
                child: CountLabel(
                  text: "طلبات الحذف",
                  stream: FirebaseFirestore.instance
                      .collection("bookings")
                      .where("teacherId", isEqualTo: teacherId)
                      .where("cancelRequested", isEqualTo: true)
                      .snapshots(),
                ),
              ),
              const Tab(text: "الدروس المقترحة"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _NewRequestsTab(),
            _CancelRequestsTab(),
            _ProposedLessonsTab(),
          ],
        ),
      ),
    );
  }
}

class _NewRequestsTab extends StatelessWidget {
  const _NewRequestsTab();

  Future<void> approveBooking(DocumentSnapshot booking) async {
    final firestore = FirebaseFirestore.instance;
    final data = booking.data() as Map<String, dynamic>;

    await firestore.collection("bookings").doc(booking.id).update({
      "status": "approved",
    });

    await firestore.collection("teacher_slots").doc(data["slotId"]).update({
      "status": "booked",
    });

    await sendNotification(
      userId: data["studentId"],
      title: "تم قبول حجزك",
      body: "تمت الموافقة على درسك يوم ${data["day"]} الساعة ${data["time"]}.",
      type: "booking_approved",
    );
  }

  Future<void> rejectBooking(DocumentSnapshot booking) async {
    final firestore = FirebaseFirestore.instance;
    final data = booking.data() as Map<String, dynamic>;

    await firestore.collection("bookings").doc(booking.id).update({
      "status": "rejected",
    });

    await firestore.collection("teacher_slots").doc(data["slotId"]).update({
      "status": "available",
    });

    await sendNotification(
      userId: data["studentId"],
      title: "تم رفض الحجز",
      body: "تم رفض طلب حجزك يوم ${data["day"]} الساعة ${data["time"]}، الرجاء اختيار موعد آخر.",
      type: "booking_rejected",
    );
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("bookings")
          .where("teacherId", isEqualTo: teacherId)
          .where("status", isEqualTo: "pending")
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("لا توجد طلبات حجز جديدة"));
        }

        final bookings = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final booking = bookings[index];
            final data = booking.data() as Map<String, dynamic>;
            final dateStr = data["date"] ?? "";

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection("users").doc(data["studentId"]).get(),
                      builder: (context, studentSnapshot) {
                        if (!studentSnapshot.hasData) {
                          return const Text("جاري التحميل...");
                        }

                        final studentData = studentSnapshot.data!.data() as Map<String, dynamic>?;
                        final studentName = studentData?["name"] ?? "طالب";

                        return Text(
                          "👤 $studentName",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text("📅 ${dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : data["day"]}"),
                    const SizedBox(height: 5),
                    Text("🕒 الوقت: ${data["time"]}"),
                    const SizedBox(height: 5),
                    Text("💰 السعر: ${data["price"]} ₪"),
                    if ((data["teacherNote"] ?? "").toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text("📝 ملاحظتك: ${data["teacherNote"]}", style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () => approveBooking(booking),
                            icon: const Icon(Icons.check),
                            label: const Text("قبول"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => rejectBooking(booking),
                            icon: const Icon(Icons.close),
                            label: const Text("رفض"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Lessons the teacher proposed directly to a specific student (via
/// "تعيين درس لهذا الطالب" on their student list). Shows ones still
/// awaiting the student's response, and ones the student rejected — for
/// rejected ones the teacher can resend to the same student (if the slot
/// is still free) or assign the lesson to a different student instead.
///
/// Filters "teacherInitiated" and "status" on the client rather than in
/// the query itself: combining them as extra equality filters alongside
/// teacherId would need a composite Firestore index, and a single-field
/// query is enough data to filter locally for this small a list.
class _ProposedLessonsTab extends StatelessWidget {
  const _ProposedLessonsTab();

  Future<void> _resendSame(BuildContext context, QueryDocumentSnapshot booking) async {
    final data = booking.data() as Map<String, dynamic>;
    final slotId = (data["slotId"] ?? "").toString();
    final studentId = (data["studentId"] ?? "").toString();
    final teacherName = (data["teacherName"] ?? "المدرب").toString();

    if (slotId.isEmpty || studentId.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    final slotRef = firestore.collection("teacher_slots").doc(slotId);

    try {
      await firestore.runTransaction((transaction) async {
        final slotSnap = await transaction.get(slotRef);
        if (!slotSnap.exists) {
          throw Exception("هذا الموعد لم يعد موجوداً، استخدم \"تعيين لطالب آخر\" لاختيار موعد جديد");
        }
        final slotData = slotSnap.data() as Map<String, dynamic>;
        if (slotData["status"] != "available") {
          throw Exception("هذا الموعد لم يعد متاحاً، استخدم \"تعيين لطالب آخر\" لاختيار موعد جديد");
        }
        transaction.update(slotRef, {"status": "pending"});
        transaction.update(booking.reference, {
          "status": "teacherProposed",
          "rejectedByStudent": FieldValue.delete(),
        });
      });

      await sendNotification(
        userId: studentId,
        title: "درس مقترح من المدرب",
        body: "أعاد $teacherName اقتراح الدرس يوم ${(data["date"] ?? "").toString().isNotEmpty ? formatIsoDateArabic(data["date"]) : data["day"]} الساعة ${data["time"]}، بانتظار موافقتك.",
        type: "teacher_proposed_lesson",
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم إعادة إرسال الاقتراح إلى نفس الطالب")),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll("Exception: ", ""))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("bookings")
          .where("teacherId", isEqualTo: teacherId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("حدث خطأ: ${snapshot.error}"));
        }

        final all = snapshot.data?.docs ?? [];
        final proposed = all.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data["teacherInitiated"] != true) return false;
          final status = data["status"];
          if (status == "teacherProposed") return true;
          if (status == "rejected" && data["rejectedByStudent"] == true) return true;
          return false;
        }).toList();

        if (proposed.isEmpty) {
          return const Center(child: Text("لا يوجد دروس مقترحة"));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: proposed.length,
          itemBuilder: (context, index) {
            final booking = proposed[index];
            final data = booking.data() as Map<String, dynamic>;
            final dateStr = (data["date"] ?? "").toString();
            final wasRejected = data["status"] == "rejected";

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection("users").doc(data["studentId"]).get(),
                      builder: (context, studentSnapshot) {
                        final studentData = studentSnapshot.data?.data() as Map<String, dynamic>?;
                        final studentName = studentData?["name"] ?? "طالب";
                        return Text(
                          "👤 $studentName",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text("📅 ${dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : data["day"]}"),
                    const SizedBox(height: 5),
                    Text("🕒 الوقت: ${data["time"]}"),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: wasRejected ? Colors.red.shade50 : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        wasRejected ? "رفض الطالب هذا الدرس المقترح" : "بانتظار رد الطالب",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: wasRejected ? Colors.red : const Color(0xff1565C0),
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (wasRejected) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _resendSame(context, booking),
                              icon: const Icon(Icons.replay, size: 16),
                              label: const Text("إعادة الإرسال لنفس الطالب", style: TextStyle(fontSize: 11.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const AssignLessonScreen()),
                                );
                              },
                              icon: const Icon(Icons.person_search, size: 16),
                              label: const Text("تعيين لطالب آخر", style: TextStyle(fontSize: 11.5)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CancelRequestsTab extends StatelessWidget {
  const _CancelRequestsTab();

  Future<void> _approveCancel(DocumentSnapshot booking) async {
    final firestore = FirebaseFirestore.instance;
    final data = booking.data() as Map<String, dynamic>;

    await firestore.collection("bookings").doc(booking.id).update({
      "status": "rejected",
      "cancelRequested": false,
    });

    if ((data["slotId"] ?? "").toString().isNotEmpty) {
      await firestore.collection("teacher_slots").doc(data["slotId"]).update({"status": "available"});
    }

    await sendNotification(
      userId: data["studentId"],
      title: "تم إلغاء الدرس",
      body: "تمت الموافقة على إلغاء درسك يوم ${data["date"] != null && data["date"].toString().isNotEmpty ? formatIsoDateArabic(data["date"]) : data["day"]} الساعة ${data["time"]}.",
      type: "lesson_cancelled",
    );
  }

  Future<void> _rejectCancel(DocumentSnapshot booking) async {
    final data = booking.data() as Map<String, dynamic>;

    await FirebaseFirestore.instance.collection("bookings").doc(booking.id).update({
      "cancelRequested": false,
    });

    await sendNotification(
      userId: data["studentId"],
      title: "تم رفض طلب الإلغاء",
      body: "لم يوافق المدرب على إلغاء درسك، الدرس ما زال قائمًا.",
      type: "cancel_rejected",
    );
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("bookings")
          .where("teacherId", isEqualTo: teacherId)
          .where("cancelRequested", isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("لا توجد طلبات إلغاء"));
        }

        final bookings = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final booking = bookings[index];
            final data = booking.data() as Map<String, dynamic>;
            final dateStr = data["date"] ?? "";

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection("users").doc(data["studentId"]).get(),
                      builder: (context, studentSnapshot) {
                        final studentData = studentSnapshot.data?.data() as Map<String, dynamic>?;
                        final studentName = studentData?["name"] ?? "طالب";

                        return Text(
                          "👤 $studentName",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text("📅 ${dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : data["day"]}"),
                    const SizedBox(height: 5),
                    Text("🕒 الوقت: ${data["time"]}"),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                      child: const Text(
                        "الطالب يريد إلغاء هذا الدرس",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => _approveCancel(booking),
                            icon: const Icon(Icons.check),
                            label: const Text("موافقة على الإلغاء"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _rejectCancel(booking),
                            icon: const Icon(Icons.close),
                            label: const Text("رفض"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

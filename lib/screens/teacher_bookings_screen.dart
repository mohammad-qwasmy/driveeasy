import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';
import '../widgets/count_label.dart';

/// Two tabs: new booking requests (status pending) and cancellation
/// requests (a student asking to cancel an already-approved lesson).
/// Approving/rejecting either removes it from this screen appropriately.
class TeacherBookingsScreen extends StatelessWidget {
  const TeacherBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser!.uid;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("طلبات الحجز"),
          centerTitle: true,
          bottom: TabBar(
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
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _NewRequestsTab(),
            _CancelRequestsTab(),
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

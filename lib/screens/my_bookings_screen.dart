import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'booking_details_screen.dart';
import '../services/app_helpers.dart';

/// "مواعيدي" — 3 tabs:
/// - القادمة: approved lessons whose real time hasn't passed yet
/// - السابقة: approved lessons whose real time has passed (shows attendance)
/// - المعلقة: still awaiting the teacher's approval
///
/// Cancelled/rejected bookings never show anywhere. Once approved, a
/// booking moves between "القادمة" and "السابقة" purely based on real
/// date/time — attendance marking has no effect on which tab it's in.
class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("bookings")
          .where("studentId", isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                title: const Text("مواعيدي"),
                centerTitle: true,
                bottom: const TabBar(
                  tabs: [Tab(text: "القادمة"), Tab(text: "السابقة"), Tab(text: "المعلقة")],
                ),
              ),
              body: const Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text("مواعيدي"), centerTitle: true),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text("تعذر التحميل: ${snapshot.error}", style: const TextStyle(color: Colors.red)),
              ),
            ),
          );
        }

        final all = snapshot.data?.docs ?? [];
        final notCancelled = all.where((d) => (d.data() as Map<String, dynamic>)["status"] != "rejected").toList();

        int _cmp(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
          final da = (a.data() as Map<String, dynamic>)["date"] ?? "";
          final db = (b.data() as Map<String, dynamic>)["date"] ?? "";
          final cmp = da.toString().compareTo(db.toString());
          if (cmp != 0) return cmp;
          final ta = (a.data() as Map<String, dynamic>)["time"] ?? "";
          final tb = (b.data() as Map<String, dynamic>)["time"] ?? "";
          return ta.toString().compareTo(tb.toString());
        }

        final pending = notCancelled.where((d) => (d.data() as Map<String, dynamic>)["status"] == "pending").toList()..sort(_cmp);

        final approved = notCancelled.where((d) => (d.data() as Map<String, dynamic>)["status"] == "approved").toList();

        final upcoming = approved.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final date = (data["date"] ?? "").toString();
          final time = (data["time"] ?? "").toString();
          if (date.isEmpty) return true;
          return !isBookingPast(date, time);
        }).toList()
          ..sort(_cmp);

        final past = approved.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final date = (data["date"] ?? "").toString();
          final time = (data["time"] ?? "").toString();
          if (date.isEmpty) return false;
          return isBookingPast(date, time);
        }).toList()
          ..sort(_cmp);

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text("مواعيدي"),
              centerTitle: true,
              bottom: TabBar(
                tabs: [
                  Tab(text: "القادمة (${upcoming.length})"),
                  Tab(text: "السابقة (${past.length})"),
                  Tab(text: "المعلقة (${pending.length})"),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _BookingsList(docs: upcoming, kind: _ListKind.upcoming, emptyMessage: "لا يوجد دروس قادمة"),
                _BookingsList(docs: past, kind: _ListKind.past, emptyMessage: "لا يوجد دروس سابقة بعد"),
                _BookingsList(docs: pending, kind: _ListKind.pending, emptyMessage: "لا يوجد حجوزات معلقة"),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _ListKind { upcoming, past, pending }

class _BookingsList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final _ListKind kind;
  final String emptyMessage;

  const _BookingsList({required this.docs, required this.kind, required this.emptyMessage});

  Future<void> _cancelPending(BuildContext context, String bookingId, String slotId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("إلغاء طلب الحجز"),
        content: const Text("هل تريد إلغاء طلب الحجز هذا؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("تراجع")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("إلغاء الطلب", style: TextStyle(color: Colors.red)),
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
  }

  Future<void> _requestCancelApproved(
    BuildContext context,
    String bookingId,
    String teacherId,
    String dateStr,
    String time,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("طلب إلغاء الدرس"),
        content: const Text(
          "هذا الدرس مؤكد بالفعل، سيتم إرسال طلب إلغاء إلى المدرب لموافقته. هل تريد المتابعة؟",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("تراجع")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("إرسال طلب الإلغاء"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection("bookings").doc(bookingId).update({
      "cancelRequested": true,
    });

    await sendNotification(
      userId: teacherId,
      title: "طلب إلغاء درس",
      body: "يريد الطالب إلغاء درسه يوم ${dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : ''} الساعة $time — راجع صفحة طلبات الحجز للموافقة أو الرفض.",
      type: "cancel_requested",
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم إرسال طلب الإلغاء إلى المدرب")),
    );
  }

  Widget _card(BuildContext context, QueryDocumentSnapshot booking) {
    final data = booking.data() as Map<String, dynamic>;
    final status = data["status"] ?? "pending";
    final dateStr = data["date"] ?? "";
    final cancelRequested = data["cancelRequested"] == true;
    final attendance = data["attendance"];

    Color statusColor = Colors.orange;
    String statusText = "قيد الانتظار";
    if (status == "approved") {
      statusColor = Colors.green;
      statusText = "مؤكد";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data["teacherName"] ?? "",
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                ),
                if (kind == _ListKind.past)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: attendance == "attended"
                          ? const Color(0xffE8F5E9)
                          : attendance == "absent"
                              ? const Color(0xffFCE9E9)
                              : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      attendance == "attended"
                          ? "حضر"
                          : attendance == "absent"
                              ? "لم يحضر"
                              : "لم يُسجَّل بعد",
                      style: TextStyle(
                        color: attendance == "attended"
                            ? Colors.green
                            : attendance == "absent"
                                ? Colors.red
                                : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.blue, size: 16),
                const SizedBox(width: 6),
                Text(
                  dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : (data["day"] ?? ""),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Text(data["time"] ?? "", style: const TextStyle(fontSize: 12.5)),
                const SizedBox(width: 14),
                const Icon(Icons.attach_money, color: Colors.green, size: 16),
                Text("${data["price"]} ₪", style: const TextStyle(fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 10),
            if (kind != _ListKind.past) ...[
              if (cancelRequested)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    "بانتظار موافقة المدرب على الإلغاء",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () {
                      if (status == "approved") {
                        _requestCancelApproved(
                          context,
                          booking.id,
                          data["teacherId"] ?? "",
                          dateStr,
                          data["time"] ?? "",
                        );
                      } else {
                        _cancelPending(context, booking.id, data["slotId"] ?? "");
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text("حذف الدرس", style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BookingDetailsScreen(booking: data),
                    ),
                  );
                },
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text("عرض التفاصيل", style: TextStyle(fontSize: 12.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Center(child: Text(emptyMessage, style: const TextStyle(fontSize: 15, color: Colors.grey)));
    }

    // Group by teacher so bookings from different teachers never mix.
    final Map<String, List<QueryDocumentSnapshot>> byTeacher = {};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final key = "${data["teacherName"] ?? "مدرب"} · ${data["licenseType"] ?? ""}";
      byTeacher.putIfAbsent(key, () => []).add(doc);
    }

    final teacherKeys = byTeacher.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: teacherKeys.length,
      itemBuilder: (context, sectionIndex) {
        final key = teacherKeys[sectionIndex];
        final sectionDocs = byTeacher[key]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (teacherKeys.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(
                  key,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xff1565C0)),
                ),
              ),
            ...sectionDocs.map((doc) => _card(context, doc)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

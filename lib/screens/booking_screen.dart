import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/app_helpers.dart';
import '../widgets/month_calendar.dart';
import 'public_profile_screen.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  bool isLoading = true;
  bool isSubmitting = false;

  List<Map<String, dynamic>> myLinks = []; // {linkId, teacherId, teacherName, licenseType}
  int selectedLinkIndex = 0;

  DateTime? selectedDate;
  final Set<String> selectedSlotIds = {};

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final linksSnap = await FirebaseFirestore.instance
        .collection("student_teacher_links")
        .where("studentId", isEqualTo: uid)
        .where("status", isEqualTo: "active")
        .get();

    final links = <Map<String, dynamic>>[];
    for (final doc in linksSnap.docs) {
      final data = doc.data();
      final teacherId = data["teacherId"] as String;
      final teacherDoc = await FirebaseFirestore.instance.collection("users").doc(teacherId).get();
      final teacherName = (teacherDoc.data() as Map<String, dynamic>?)?["name"] ?? "";
      links.add({
        "linkId": doc.id,
        "teacherId": teacherId,
        "teacherName": teacherName,
        "licenseType": data["licenseType"] ?? "",
      });
    }

    if (!mounted) return;
    setState(() {
      myLinks = links;
      isLoading = false;
    });
  }

  Map<String, dynamic>? get _currentLink =>
      myLinks.isEmpty ? null : myLinks[selectedLinkIndex];

  /// Books every selected slot, one Firestore transaction per slot, so two
  /// students can never take the same slot and the same student can't
  /// double-book one. Slots that got taken in the meantime are reported
  /// back instead of silently failing.
  ///
  /// Also guards against a student booking two lessons at the exact same
  /// date/time with two *different* teachers (e.g. one teacher per license
  /// type): before confirming each slot we check the student's own
  /// pending/approved bookings (across all teachers) for a same date+time
  /// match, and skip that slot with a clear message if one is found.
  Future<void> confirmBooking() async {
    if (selectedSlotIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اختر موعداً واحداً على الأقل")),
      );
      return;
    }

    final link = _currentLink;
    if (link == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => isSubmitting = true);

    final firestore = FirebaseFirestore.instance;
    int succeeded = 0;
    final failedMessages = <String>[];

    // Snapshot of the student's own active bookings (any teacher) as
    // "date|time" keys, so we can catch same-time conflicts across
    // different teachers. Updated as we succeed within this same
    // submission too, so booking two conflicting slots in one go is
    // also blocked.
    final existingBookingsSnap = await firestore
        .collection("bookings")
        .where("studentId", isEqualTo: user.uid)
        .where("status", whereIn: ["pending", "approved"])
        .get();

    final bookedTimeKeys = <String>{
      for (final doc in existingBookingsSnap.docs)
        "${(doc.data())["date"]}|${(doc.data())["time"]}",
    };

    for (final slotId in selectedSlotIds.toList()) {
      final slotRef = firestore.collection("teacher_slots").doc(slotId);
      final bookingRef = firestore.collection("bookings").doc();

      try {
        // Read the slot first (outside the transaction) just to check for
        // a same-time conflict with the student's other bookings. The
        // transaction below still re-verifies availability atomically.
        final preCheckSnap = await slotRef.get();
        if (!preCheckSnap.exists) {
          throw Exception("موعد لم يعد موجوداً");
        }
        final preCheckData = preCheckSnap.data() as Map<String, dynamic>;
        final slotDate = preCheckData["date"] ?? "";
        final slotTime = "${preCheckData["startTime"]} - ${preCheckData["endTime"]}";
        final timeKey = "$slotDate|$slotTime";

        if (bookedTimeKeys.contains(timeKey)) {
          throw Exception(
            "لديك موعد آخر محجوز في نفس الوقت (${preCheckData["startTime"]}) بتاريخ ${preCheckData["date"]}",
          );
        }

        await firestore.runTransaction((transaction) async {
          final slotSnap = await transaction.get(slotRef);

          if (!slotSnap.exists) {
            throw Exception("موعد لم يعد موجوداً");
          }

          final slotData = slotSnap.data() as Map<String, dynamic>;

          if (slotData["status"] != "available") {
            throw Exception("موعد ${slotData["startTime"]} تم حجزه من طالب آخر");
          }

          transaction.update(slotRef, {"status": "pending"});

          transaction.set(bookingRef, {
            "studentId": user.uid,
            "teacherId": link["teacherId"],
            "teacherName": link["teacherName"],
            "licenseType": link["licenseType"],
            "day": slotData["day"] ?? "",
            "date": slotData["date"] ?? "",
            "time": "${slotData["startTime"]} - ${slotData["endTime"]}",
            "price": slotData["price"].toString(),
            "slotId": slotId,
            "status": "pending",
            "attendance": null,
            "createdAt": Timestamp.now(),
          });
        });
        succeeded++;
        bookedTimeKeys.add(timeKey);

        final studentDoc = await firestore.collection("users").doc(user.uid).get();
        final studentName = (studentDoc.data() as Map<String, dynamic>?)?["name"] ?? "طالب";
        await sendNotification(
          userId: link["teacherId"],
          title: "طلب حجز جديد",
          body: "$studentName يطلب حجز درس، بانتظار موافقتك.",
          type: "booking_requested",
        );
      } catch (e) {
        failedMessages.add(e.toString().replaceAll("Exception: ", ""));
      }
    }

    if (!mounted) return;
    setState(() {
      isSubmitting = false;
      selectedSlotIds.clear();
    });

    if (failedMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم إرسال $succeeded طلب حجز، بانتظار موافقة المدرب")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم حجز $succeeded، وتعذر حجز: ${failedMessages.join('، ')}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (myLinks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("حجز درس"), centerTitle: true),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              "لا يمكنك حجز درس حتى تتم الموافقة على طلب التسجيل من مدرب.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ),
        ),
      );
    }

    final link = _currentLink!;
    final teacherId = link["teacherId"] as String;

    return Scaffold(
      appBar: AppBar(title: const Text("حجز درس قيادة"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (myLinks.length > 1) ...[
              const Text(
                "اختر المدرب / نوع الرخصة",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: myLinks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final isSelected = i == selectedLinkIndex;
                    return ChoiceChip(
                      label: Text("${myLinks[i]["teacherName"]} · ${myLinks[i]["licenseType"]}"),
                      selected: isSelected,
                      onSelected: (_) => setState(() {
                        selectedLinkIndex = i;
                        selectedDate = null;
                        selectedSlotIds.clear();
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PublicProfileScreen(userId: teacherId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                  label: const Text("عرض ملف المدرب المختار"),
                ),
              ),
              const SizedBox(height: 8),
            ] else
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(link["teacherName"]),
                  subtitle: Text("رخصة ${link["licenseType"]}"),
                  trailing: IconButton(
                    tooltip: "عرض الملف الشخصي",
                    icon: const Icon(Icons.remove_red_eye_outlined, color: Colors.blue),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PublicProfileScreen(userId: teacherId),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              "اختر يوماً من الشهر لعرض الأوقات المتاحة فيه",
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
                        selectedSlotIds.clear();
                      }),
                    );
                  },
                ),
              ),
            ),
            if (selectedDate != null) ...[
              const SizedBox(height: 18),
              Text(
                "الأوقات المتاحة يوم ${formatIsoDateArabic(isoDate(selectedDate!))} (يمكنك اختيار أكثر من موعد)",
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

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text("لا يوجد أوقات متاحة في هذا اليوم"),
                    );
                  }

                  final slots = [...snapshot.data!.docs]
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
                      child: Text("لا يوجد أوقات متاحة متبقية في هذا اليوم"),
                    );
                  }

                  return Column(
                    children: slots.map((item) {
                      final data = item.data() as Map<String, dynamic>;
                      final selected = selectedSlotIds.contains(item.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: selected ? const Color(0xff1565C0) : Colors.grey.shade300,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: selected,
                          onChanged: (_) => setState(() {
                            if (selected) {
                              selectedSlotIds.remove(item.id);
                            } else {
                              selectedSlotIds.add(item.id);
                            }
                          }),
                          secondary: Icon(
                            Icons.access_time,
                            color: selected ? const Color(0xff1565C0) : Colors.grey,
                          ),
                          title: Text("${data["startTime"]} - ${data["endTime"]}"),
                          subtitle: Text("${data["price"]} ₪"),
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
                onPressed: isSubmitting ? null : confirmBooking,
                child: isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        selectedSlotIds.length > 1
                            ? "تأكيد حجز ${selectedSlotIds.length} دروس"
                            : "تأكيد الحجز",
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

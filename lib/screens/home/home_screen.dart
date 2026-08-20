import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../booking_screen.dart';
import '../my_bookings_screen.dart';
import '../notifications_screen.dart';
import '../profile_screen.dart';
import '../my_plan_screen.dart';
import '../my_lessons_screen.dart';
import '../chat_screen.dart';
import '../teacher_link_screen.dart';
import '../public_profile_screen.dart';
import '../../services/app_helpers.dart';
import '../../services/app_language.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> myLinks = []; // {linkId, teacherId, teacherName, licenseType, testDate, testTime}
  bool loadedLinks = false;

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
        "testDate": data["testDate"] ?? "",
        "testTime": data["testTime"] ?? "",
      });
    }

    if (!mounted) return;
    setState(() {
      myLinks = links;
      loadedLinks = true;
    });
  }

  Stream<QuerySnapshot> _upcomingLessonStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('studentId', isEqualTo: uid)
        .where('status', isEqualTo: 'approved')
        .snapshots();
  }

  Map<String, dynamic>? _nearestUpcoming(List<QueryDocumentSnapshot> docs) {
    final upcoming = docs.map((d) => d.data() as Map<String, dynamic>).where((data) {
      final date = (data["date"] ?? "") as String;
      final time = (data["time"] ?? "").toString();
      if (date.isEmpty) return false;
      return !isBookingPast(date, time);
    }).toList()
      ..sort((a, b) {
        final cmp = (a["date"] as String).compareTo(b["date"] as String);
        if (cmp != 0) return cmp;
        return (a["time"] ?? "").toString().compareTo((b["time"] ?? "").toString());
      });
    return upcoming.isEmpty ? null : upcoming.first;
  }

  Future<void> _openChat() async {
    if (myLinks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يجب التسجيل مع مدرب أولاً لبدء المحادثة")),
      );
      return;
    }

    if (myLinks.length == 1) {
      final link = myLinks.first;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            studentId: FirebaseAuth.instance.currentUser!.uid,
            teacherId: link["teacherId"],
            otherUserName: link["teacherName"],
          ),
        ),
      );
      return;
    }

    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("اختر المدرب"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: myLinks
              .map((link) => ListTile(
                    leading: const Icon(Icons.person, color: Color(0xff1565C0)),
                    title: Text(link["teacherName"]),
                    subtitle: Text("رخصة ${link["licenseType"]}"),
                    onTap: () => Navigator.pop(ctx, link),
                  ))
              .toList(),
        ),
      ),
    );

    if (chosen == null || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          studentId: FirebaseAuth.instance.currentUser!.uid,
          teacherId: chosen["teacherId"],
          otherUserName: chosen["teacherName"],
        ),
      ),
    );
  }

  Widget quickTile({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
        trailing: const Icon(Icons.chevron_left, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F8FD),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Text(
          tr("app_name"),
          style: const TextStyle(color: Color(0xff1565C0), fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
            icon: const Icon(Icons.notifications_none_rounded, color: Color(0xff1565C0)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xff1565C0), Color(0xff42A5F5)],
                ),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_car_filled, color: Colors.white, size: 30),
                  SizedBox(height: 10),
                  Text(
                    "كل درس يقربك خطوة من رخصتك 🚗",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // My teacher(s) — quick access to view their profile and rate
            // them, reachable directly from the student's home screen
            // instead of only through the booking flow.
            if (myLinks.isNotEmpty)
              Card(
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
                      child: Text(
                        "مدربي",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    ...myLinks.map((link) => ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(link["teacherName"] ?? ""),
                          subtitle: Text("رخصة ${link["licenseType"] ?? ""}"),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(userId: link["teacherId"]),
                              ),
                            );
                          },
                        )),
                  ],
                ),
              ),

            // Nudge: if the student never finished linking with a teacher
            // (e.g. they closed the app mid-onboarding), always give them a
            // clear way back into that flow instead of getting stuck.
            if (myLinks.isEmpty && loadedLinks)
              Card(
                color: const Color(0xffFFF4E5),
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TeacherLinkScreen()),
                  ),
                  leading: const Icon(Icons.person_search_rounded, color: Colors.orange),
                  title: const Text(
                    "لست مرتبطًا بمدرب بعد",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  subtitle: const Text("اضغط هنا لاختيار مدرب وبدء الحجز", style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_left),
                ),
              ),

            // Test dates — one card per teacher that has set one. Shown
            // topmost so it's the most prominent thing the student sees.
            ...myLinks.where((l) => (l["testDate"] ?? "").toString().isNotEmpty).map((link) {
              return Card(
                elevation: 1.5,
                color: const Color(0xffFFF4E5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded, color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "موعد اختبار رخصة ${link["licenseType"]}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              formatIsoDateTimeArabic(link["testDate"].toString(), link["testTime"].toString()),
                              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Next lesson — wired to Firestore: nearest approved lesson from
            // today onward. Once that day passes it naturally rolls to the
            // next one since the query is date/time ordered.
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, color: Color(0xff1565C0), size: 18),
                        const SizedBox(width: 8),
                        Text(tr("home_next_lesson"), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<QuerySnapshot>(
                      stream: _upcomingLessonStream(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(
                            "تعذر تحميل الدرس القادم: ${snapshot.error}",
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          );
                        }

                        final booking = snapshot.hasData
                            ? _nearestUpcoming(snapshot.data!.docs)
                            : null;

                        if (booking == null) {
                          return const Text(
                            "لا يوجد لديك دروس قادمة مؤكدة بعد",
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          );
                        }

                        final dateStr = booking["date"] ?? "";

                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dateStr.isNotEmpty ? formatIsoDateArabic(dateStr) : (booking['day'] ?? ""),
                                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${booking['time']} · ${booking['teacherName']}",
                                    style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xffE8F5E9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                "مؤكد",
                                style: TextStyle(color: Colors.green, fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Align(
              alignment: Alignment.centerRight,
              child: Text(
                tr("home_quick_services"),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
              ),
            ),
            const SizedBox(height: 10),

            quickTile(
              title: tr("book_lesson"),
              icon: Icons.calendar_month_rounded,
              color: Colors.blue,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingScreen())),
            ),
            quickTile(
              title: tr("teacher_link"),
              icon: Icons.person_search_rounded,
              color: Colors.deepOrange,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherLinkScreen())),
            ),
            quickTile(
              title: tr("my_bookings"),
              icon: Icons.event_available_rounded,
              color: Colors.green,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
            ),
            quickTile(
              title: tr("my_plan"),
              icon: Icons.flag_rounded,
              color: Colors.teal,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPlanScreen())),
            ),
            quickTile(
              title: tr("my_lessons"),
              icon: Icons.menu_book_rounded,
              color: Colors.indigo,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyLessonsScreen())),
            ),
            quickTile(
              title: tr("chat_with_teacher"),
              icon: Icons.chat_bubble_rounded,
              color: Colors.pink,
              onTap: _openChat,
            ),
            quickTile(
              title: tr("my_account"),
              icon: Icons.person_rounded,
              color: Colors.purple,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

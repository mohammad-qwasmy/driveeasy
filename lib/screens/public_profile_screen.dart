import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/app_helpers.dart';
import '../services/app_language.dart';

/// Read-only profile view of *another* user — used so students and
/// teachers can look at each other's profile. Unlike [ProfileScreen],
/// this never shows edit/delete/logout controls; it's purely informational,
/// plus a "rate teacher" action when applicable.
class PublicProfileScreen extends StatefulWidget {
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool isLoading = true;
  bool canRate = false;
  int? myExistingRating;

  Map<String, dynamic> data = {};
  String schoolName = "";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final firestore = FirebaseFirestore.instance;
    final doc = await firestore.collection("users").doc(widget.userId).get();
    final userData = doc.data() ?? {};

    String fetchedSchoolName = "";
    final schoolId = userData["schoolId"] ?? "";
    if (userData["role"] == "teacher" && schoolId.toString().isNotEmpty) {
      final schoolDoc = await firestore.collection("schools").doc(schoolId).get();
      fetchedSchoolName = (schoolDoc.data() as Map<String, dynamic>?)?["name"] ?? "";
    }

    // A student can only rate a teacher they're actually (actively) linked
    // to — never a random teacher they merely browsed.
    bool allowedToRate = false;
    int? existingStars;
    final me = FirebaseAuth.instance.currentUser;
    if (me != null && userData["role"] == "teacher" && me.uid != widget.userId) {
      final linkSnap = await firestore
          .collection("student_teacher_links")
          .where("studentId", isEqualTo: me.uid)
          .where("teacherId", isEqualTo: widget.userId)
          .where("status", isEqualTo: "active")
          .limit(1)
          .get();
      allowedToRate = linkSnap.docs.isNotEmpty;

      final myRatingDoc = await firestore
          .collection("teacher_ratings")
          .doc("${me.uid}_${widget.userId}")
          .get();
      if (myRatingDoc.exists) {
        existingStars = ((myRatingDoc.data()?["stars"] ?? 0) as num).toInt();
      }
    }

    if (!mounted) return;
    setState(() {
      data = userData;
      schoolName = fetchedSchoolName;
      canRate = allowedToRate;
      myExistingRating = existingStars;
      isLoading = false;
    });
  }

  Future<void> _openRatingDialog() async {
    int selected = myExistingRating ?? 5;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text("قيّم المدرب"),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final starIndex = i + 1;
                  return IconButton(
                    onPressed: () => setDialogState(() => selected = starIndex),
                    icon: Icon(
                      starIndex <= selected ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                  );
                }),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text("إرسال"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    await rateTeacher(teacherId: widget.userId, studentId: me.uid, stars: result);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("شكراً لتقييمك")),
    );
    _load();
  }

  Widget _infoTile(IconData icon, String title, String value) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        subtitle: Text(value.isEmpty ? tr("not_available") : value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final role = data["role"] ?? "";
    final isTeacher = role == "teacher";
    final name = data["name"] ?? "";
    final phone = data["phone"] ?? "";
    final city = data["city"] ?? "";
    final licenseType = data["licenseType"] ?? "";
    final double rating = ((data["rating"] ?? 0) as num).toDouble();
    final int ratingCount = ((data["ratingCount"] ?? 0) as num).toInt();

    String? photoBase64 = data["profileImage"];
    ImageProvider? avatarImage;
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(photoBase64));
      } catch (_) {
        avatarImage = null;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text("الملف الشخصي"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 55,
              backgroundColor: Colors.blue,
              backgroundImage: avatarImage,
              child: avatarImage == null
                  ? const Icon(Icons.person, size: 60, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 15),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(
              isTeacher ? tr("teacher") : tr("student"),
              style: const TextStyle(color: Colors.grey, fontSize: 18),
            ),
            if (isTeacher) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 22),
                  const SizedBox(width: 4),
                  Text(
                    ratingCount == 0
                        ? "لا يوجد تقييمات بعد"
                        : "${rating.toStringAsFixed(1)} ($ratingCount تقييم)",
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 25),
            _infoTile(Icons.phone, tr("phone"), phone),
            _infoTile(Icons.location_city, tr("city"), city),
            if (licenseType.toString().isNotEmpty)
              _infoTile(Icons.badge, tr("license_type"), licenseType),
            if (isTeacher && schoolName.isNotEmpty)
              _infoTile(Icons.school, "المدرسة", schoolName),
            if (canRate) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
                  onPressed: _openRatingDialog,
                  icon: const Icon(Icons.star, color: Colors.white),
                  label: Text(
                    myExistingRating == null ? "قيّم المدرب" : "تعديل تقييمك",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

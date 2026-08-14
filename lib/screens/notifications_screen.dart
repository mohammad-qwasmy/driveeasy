import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// Real notifications, written by teacher actions (approve/reject a
/// booking, mark a plan step done) — no static/fake data.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _iconFor(String type) {
    switch (type) {
      case "booking_approved":
        return Icons.check_circle;
      case "booking_rejected":
        return Icons.cancel;
      case "plan_update":
        return Icons.flag_rounded;
      default:
        return Icons.notifications;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case "booking_approved":
        return Colors.green;
      case "booking_rejected":
        return Colors.red;
      case "plan_update":
        return Colors.teal;
      default:
        return Colors.blue;
    }
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return "";
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return "الآن";
    if (diff.inMinutes < 60) return "منذ ${diff.inMinutes} دقيقة";
    if (diff.inHours < 24) return "منذ ${diff.inHours} ساعة";
    return DateFormat("d/M/yyyy").format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xffF5F9FF),
      appBar: AppBar(title: const Text("الإشعارات"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("notifications")
            .where("userId", isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final ta = (a.data() as Map<String, dynamic>)["createdAt"] as Timestamp?;
              final tb = (b.data() as Map<String, dynamic>)["createdAt"] as Timestamp?;
              if (ta == null || tb == null) return 0;
              return tb.compareTo(ta);
            });

          if (docs.isEmpty) {
            return const Center(child: Text("لا توجد إشعارات بعد", style: TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final type = data["type"] ?? "general";
              final isRead = data["read"] == true;

              return Card(
                elevation: isRead ? 1 : 3,
                color: isRead ? Colors.white : const Color(0xffF0F6FF),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  onTap: () => doc.reference.update({"read": true}),
                  leading: CircleAvatar(
                    backgroundColor: _colorFor(type).withOpacity(0.15),
                    child: Icon(_iconFor(type), color: _colorFor(type)),
                  ),
                  title: Text(
                    data["title"] ?? "",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data["body"] ?? ""),
                      const SizedBox(height: 5),
                      Text(
                        _timeAgo(data["createdAt"] as Timestamp?),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: isRead
                      ? null
                      : Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

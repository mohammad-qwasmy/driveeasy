import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Schools that an admin has deleted are only soft-deleted (flagged with
/// isDeleted: true), never actually removed from Firestore — so their
/// teachers' schoolId links stay intact. This screen lets an admin bring a
/// school back exactly as it was, teachers included.
class DeletedSchoolsScreen extends StatelessWidget {
  const DeletedSchoolsScreen({super.key});

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat("d/M/yyyy").format(ts.toDate());
    }
    return "غير متوفر";
  }

  Future<void> _restoreSchool(BuildContext context, String schoolId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("استعادة المدرسة"),
        content: Text("هل تريد استعادة مدرسة \"$name\"؟ سيعود إليها نفس المدربين الذين كانوا فيها."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("استعادة"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection("schools").doc(schoolId).update({
      "isDeleted": false,
      "deletedAt": FieldValue.delete(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("المدارس المحذوفة"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("schools").snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("حدث خطأ: ${snapshot.error}"));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final deletedSchools = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data["isDeleted"] == true;
          }).toList();

          if (deletedSchools.isEmpty) {
            return const Center(
              child: Text("لا يوجد مدارس محذوفة", style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: deletedSchools.length,
            itemBuilder: (context, index) {
              final doc = deletedSchools[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = data["name"] ?? "";

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade400,
                    child: const Icon(Icons.school, color: Colors.white),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("تاريخ الحذف: ${_formatDate(data["deletedAt"])}"),
                  // A ListTile's trailing widget must fit inside a bounded
                  // width, or Flutter throws a layout assertion (which
                  // showed up in production as a plain white/blank screen
                  // instead of a normal error page). Wrapping this button
                  // in a fixed-width SizedBox guarantees that width.
                  trailing: SizedBox(
                    width: 110,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => _restoreSchool(context, doc.id, name),
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text("استعادة", style: TextStyle(fontSize: 12.5)),
                    ),
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

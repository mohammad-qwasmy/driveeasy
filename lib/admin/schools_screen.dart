import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'school_details_screen.dart';
import 'deleted_schools_screen.dart';

/// Admin screen to manage driving schools. Every teacher must belong to
/// exactly one school; students pick a school first, then only see the
/// teachers that belong to it.
class SchoolsScreen extends StatefulWidget {
  const SchoolsScreen({super.key});

  @override
  State<SchoolsScreen> createState() => _SchoolsScreenState();
}

class _SchoolsScreenState extends State<SchoolsScreen> {
  Future<void> _createSchool() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("إنشاء مدرسة جديدة"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "اسم المدرسة",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("إنشاء"),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    await FirebaseFirestore.instance.collection("schools").add({
      "name": name,
      "createdAt": Timestamp.now(),
      "isDeleted": false,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("تم إنشاء مدرسة \"$name\"")),
    );
  }

  Future<void> _deleteSchool(String schoolId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف المدرسة"),
        content: Text(
          "هل أنت متأكد من حذف مدرسة \"$name\"؟ يمكنك استعادتها لاحقًا مع نفس المدربين من \"المدارس المحذوفة\".",
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

    // Soft delete: the school is just hidden, never actually removed, so
    // teachers keep their schoolId and reappear as-is if it's restored.
    await FirebaseFirestore.instance.collection("schools").doc(schoolId).update({
      "isDeleted": true,
      "deletedAt": Timestamp.now(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("المدارس"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: "المدارس المحذوفة",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeletedSchoolsScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSchool,
        icon: const Icon(Icons.add),
        label: const Text("إنشاء مدرسة"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("schools").orderBy("createdAt").snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final schools = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data["isDeleted"] != true;
          }).toList();

          if (schools.isEmpty) {
            return const Center(
              child: Text("لا يوجد مدارس بعد — اضغط \"إنشاء مدرسة\" للبدء", style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: schools.length,
            itemBuilder: (context, index) {
              final school = schools[index];
              final name = (school.data() as Map<String, dynamic>)["name"] ?? "";

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SchoolDetailsScreen(schoolId: school.id, schoolName: name),
                      ),
                    );
                  },
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xff1565C0),
                    child: Icon(Icons.school, color: Colors.white),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection("users")
                        .where("role", isEqualTo: "teacher")
                        .where("schoolId", isEqualTo: school.id)
                        .snapshots(),
                    builder: (context, teacherSnap) {
                      final count = teacherSnap.data?.docs.length ?? 0;
                      return Text("عدد المدربين: $count");
                    },
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteSchool(school.id, name),
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

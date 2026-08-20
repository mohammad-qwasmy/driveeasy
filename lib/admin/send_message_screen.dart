import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Lets an admin broadcast a message to students, teachers, or both -
/// either to the whole group or to hand-picked individuals (e.g. one
/// specific teacher). Each recipient gets a regular entry in the
/// "notifications" collection (same collection students/teachers already
/// see in NotificationsScreen), with type "admin_message".
///
/// Admins can also save frequently-used messages as templates ("رسائل
/// محفوظة") so they don't have to retype them every time - tapping a saved
/// template fills the text box, and templates stay saved permanently until
/// the admin deletes them.
enum _Audience { students, teachers, both }

class SendMessageScreen extends StatefulWidget {
  const SendMessageScreen({super.key});

  @override
  State<SendMessageScreen> createState() => _SendMessageScreenState();
}

class _SendMessageScreenState extends State<SendMessageScreen> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final TextEditingController titleController =
      TextEditingController(text: "رسالة من الإدارة");
  final TextEditingController bodyController = TextEditingController();

  _Audience audience = _Audience.both;
  bool isSending = false;

  // When true (and audience is students or teachers, not "both"), the
  // admin hand-picks specific people instead of messaging the whole group.
  bool pickSpecificPeople = false;
  final Set<String> selectedUserIds = {};

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  List<String> _rolesForAudience() {
    switch (audience) {
      case _Audience.students:
        return ["student"];
      case _Audience.teachers:
        return ["teacher"];
      case _Audience.both:
        return ["student", "teacher"];
    }
  }

  Future<void> _sendMessage() async {
    if (bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اكتب نص الرسالة أولاً")),
      );
      return;
    }

    if (pickSpecificPeople && audience != _Audience.both && selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اختر شخصًا واحدًا على الأقل")),
      );
      return;
    }

    setState(() => isSending = true);

    try {
      final roles = _rolesForAudience();

      final usersSnapshot = await firestore
          .collection("users")
          .where("role", whereIn: roles)
          .get();

      var recipients = usersSnapshot.docs.where((doc) {
        final data = doc.data();
        return data["isDeleted"] != true && data["isBlocked"] != true;
      }).toList();

      if (pickSpecificPeople && audience != _Audience.both) {
        recipients = recipients.where((d) => selectedUserIds.contains(d.id)).toList();
      }

      if (recipients.isEmpty) {
        if (!mounted) return;
        setState(() => isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("لا يوجد مستلمون مطابقون")),
        );
        return;
      }

      final batch = firestore.batch();
      for (final userDoc in recipients) {
        final notifRef = firestore.collection("notifications").doc();
        batch.set(notifRef, {
          "userId": userDoc.id,
          "type": "admin_message",
          "title": titleController.text.trim().isEmpty
              ? "رسالة من الإدارة"
              : titleController.text.trim(),
          "body": bodyController.text.trim(),
          "read": false,
          "createdAt": Timestamp.now(),
        });
      }
      await batch.commit();

      if (!mounted) return;
      setState(() => isSending = false);
      bodyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم إرسال الرسالة إلى ${recipients.length} مستخدم")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("حدث خطأ أثناء الإرسال: $e")),
      );
    }
  }

  Future<void> _saveAsTemplate() async {
    if (bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اكتب نص الرسالة أولاً لحفظها")),
      );
      return;
    }

    await firestore.collection("admin_message_templates").add({
      "title": titleController.text.trim().isEmpty
          ? "رسالة من الإدارة"
          : titleController.text.trim(),
      "body": bodyController.text.trim(),
      "createdAt": Timestamp.now(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم حفظ الرسالة في القائمة الجاهزة")),
    );
  }

  Widget _audienceChip(String label, _Audience value, IconData icon) {
    final selected = audience == value;
    return ChoiceChip(
      label: Text(label),
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : Colors.blue),
      selected: selected,
      selectedColor: Colors.blue,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
      onSelected: (_) {
        setState(() {
          audience = value;
          selectedUserIds.clear();
          if (value == _Audience.both) pickSpecificPeople = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F9FF),
      appBar: AppBar(
        title: const Text("إرسال رسالة"),
        backgroundColor: Colors.blue,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "إرسال إلى:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      _audienceChip("الطلاب", _Audience.students, Icons.school),
                      _audienceChip("المدربون", _Audience.teachers, Icons.badge),
                      _audienceChip("الطلاب والمدربون", _Audience.both, Icons.groups),
                    ],
                  ),
                  if (audience != _Audience.both) ...[
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        audience == _Audience.students
                            ? "تحديد طلاب معينين بدل الجميع"
                            : "تحديد مدربين معينين بدل الجميع",
                      ),
                      value: pickSpecificPeople,
                      onChanged: (v) => setState(() {
                        pickSpecificPeople = v;
                        selectedUserIds.clear();
                      }),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: "عنوان الرسالة",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: "نص الرسالة",
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            if (pickSpecificPeople && audience != _Audience.both) ...[
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    audience == _Audience.students ? "اختر الطلاب" : "اختر المدربين",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(
                height: 220,
                child: StreamBuilder<QuerySnapshot>(
                  stream: firestore
                      .collection("users")
                      .where("role", isEqualTo: audience == _Audience.students ? "student" : "teacher")
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final people = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data["isDeleted"] != true;
                    }).toList();

                    if (people.isEmpty) {
                      return const Center(child: Text("لا يوجد نتائج"));
                    }

                    return ListView.builder(
                      itemCount: people.length,
                      itemBuilder: (context, index) {
                        final doc = people[index];
                        final data = doc.data() as Map<String, dynamic>;
                        return CheckboxListTile(
                          dense: true,
                          value: selectedUserIds.contains(doc.id),
                          title: Text(data["name"] ?? ""),
                          subtitle: Text(data["email"] ?? ""),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                selectedUserIds.add(doc.id);
                              } else {
                                selectedUserIds.remove(doc.id);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saveAsTemplate,
                      icon: const Icon(Icons.push_pin),
                      label: const Text("حفظ كرسالة جاهزة"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: isSending ? null : _sendMessage,
                      icon: isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      label: const Text("إرسال", style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "الرسائل الجاهزة (اضغط لاستخدام أي رسالة)",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: firestore
                    .collection("admin_message_templates")
                    .orderBy("createdAt", descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final templates = snapshot.data!.docs;

                  if (templates.isEmpty) {
                    return const Center(
                      child: Text(
                        "لا يوجد رسائل جاهزة بعد",
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: templates.length,
                    itemBuilder: (context, index) {
                      final doc = templates[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: ListTile(
                          leading: const Icon(Icons.push_pin, color: Colors.blue),
                          title: Text(
                            data["title"] ?? "",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            data["body"] ?? "",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            setState(() {
                              titleController.text = data["title"] ?? "";
                              bodyController.text = data["body"] ?? "";
                            });
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text("حذف الرسالة الجاهزة"),
                                  content: const Text("هل تريد حذف هذه الرسالة من القائمة الجاهزة؟"),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text("إلغاء"),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text("حذف", style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await doc.reference.delete();
                              }
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

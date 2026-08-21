import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../widgets/count_label.dart';
import '../screens/public_profile_screen.dart';

class TeachersScreen extends StatefulWidget {
  const TeachersScreen({super.key});

  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  final CollectionReference users = FirebaseFirestore.instance.collection("users");
  String searchQuery = "";

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat("d/M/yyyy").format(ts.toDate());
    }
    return "غير متوفر";
  }

  Widget _detailLine(IconData icon, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: CountLabel(
          text: "إدارة المدربين",
          stream: users.where("role", isEqualTo: "teacher").snapshots(),
        ),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            tooltip: "المدربون المحذوفون",
            icon: const Icon(Icons.restore_from_trash),
            onPressed: () => _showDeletedTeachers(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: "ابحث عن مدرب بالاسم أو الهاتف أو البريد",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() => searchQuery = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: users.where("role", isEqualTo: "teacher").snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("لا يوجد مدربون", style: TextStyle(fontSize: 18)),
                  );
                }

                var teachers = snapshot.data!.docs
                    .where((doc) => (doc.data() as Map<String, dynamic>)["isDeleted"] != true)
                    .toList();

                if (searchQuery.isNotEmpty) {
                  teachers = teachers.where((doc) {
                    final t = doc.data() as Map<String, dynamic>;
                    final name = (t["name"] ?? "").toString().toLowerCase();
                    final phone = (t["phone"] ?? "").toString().toLowerCase();
                    final email = (t["email"] ?? "").toString().toLowerCase();
                    return name.contains(searchQuery) ||
                        phone.contains(searchQuery) ||
                        email.contains(searchQuery);
                  }).toList();
                }

                if (teachers.isEmpty) {
                  return const Center(
                    child: Text("لا يوجد نتائج مطابقة", style: TextStyle(fontSize: 16)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: teachers.length,
                  itemBuilder: (context, index) {
                    final teacher = teachers[index].data() as Map<String, dynamic>;
                    final docId = teachers[index].id;
                    final isBlocked = teacher["isBlocked"] == true;
                    final name = (teacher["name"] ?? "").toString().trim();

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PublicProfileScreen(userId: docId),
                            ),
                          );
                        },
                        leading: _teacherAvatar(teacher["profileImage"]),
                        title: Text(
                          name.isNotEmpty ? name : "مدرب بدون اسم",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Row(
                          children: [
                            Icon(
                              isBlocked ? Icons.cancel : Icons.verified,
                              color: isBlocked ? Colors.red : Colors.green,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isBlocked ? "الحساب معطل" : "الحساب مفعل",
                              style: TextStyle(
                                color: isBlocked ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == "toggle") {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(isBlocked ? "تفعيل المدرب" : "تعطيل المدرب"),
                                  content: Text(
                                    isBlocked
                                        ? "هل أنت متأكد من تفعيل حساب $name؟"
                                        : "هل أنت متأكد من تعطيل حساب $name؟ لن يتمكن من تسجيل الدخول.",
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text("تأكيد"),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              await users.doc(docId).update({"isBlocked": !isBlocked});
                            } else if (value == "delete") {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text("حذف المدرب"),
                                  content: Text(
                                    "سيتم تعطيل حساب $name فوراً. تبقى بياناته محفوظة لمدة 30 يوماً "
                                    "يمكنه خلالها استعادة حسابه بنفسه عبر تسجيل الدخول، وبعدها يُحذف نهائياً "
                                    "بشكل لا رجعة فيه.",
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

                              final now = DateTime.now();
                              await FirebaseFirestore.instance.collection("users").doc(docId).update({
                                "isDeleted": true,
                                "deletedAt": Timestamp.fromDate(now),
                                "purgeAt": Timestamp.fromDate(now.add(const Duration(days: 30))),
                              });

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "تم حذف المدرب، وسيبقى قابلاً للاستعادة لمدة 30 يوماً",
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: "toggle",
                              child: Row(
                                children: [
                                  Icon(isBlocked ? Icons.check_circle : Icons.block,
                                      color: isBlocked ? Colors.green : Colors.orange, size: 18),
                                  const SizedBox(width: 8),
                                  Text(isBlocked ? "تفعيل" : "تعطيل"),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: "delete",
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red, size: 18),
                                  SizedBox(width: 8),
                                  Text("حذف"),
                                ],
                              ),
                            ),
                          ],
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
    );
  }

  Widget _teacherAvatar(String? profileImage) {
    if (profileImage != null && profileImage.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 22,
          backgroundImage: MemoryImage(base64Decode(profileImage)),
        );
      } catch (_) {
        // Fall through to the default icon avatar below.
      }
    }
    return const CircleAvatar(
      radius: 22,
      backgroundColor: Color(0xff1565C0),
      child: Icon(Icons.person, color: Colors.white),
    );
  }

  void _showDeletedTeachers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _DeletedTeachersScreen(),
      ),
    );
  }
}

class _DeletedTeachersScreen extends StatelessWidget {
  const _DeletedTeachersScreen();

  @override
  Widget build(BuildContext context) {
    final users = FirebaseFirestore.instance.collection("users");

    return Scaffold(
      appBar: AppBar(
        title: const Text("المدربون المحذوفون"),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // A single-field query (role only) always works without needing a
        // Firestore composite index; we filter isDeleted on the client
        // instead of combining two equality filters server-side, which
        // was silently failing (and showing a blank page) whenever the
        // matching composite index hadn't been created for this project.
        stream: users.where("role", isEqualTo: "teacher").snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("حدث خطأ: ${snapshot.error}"));
          }

          final deleted = (snapshot.data?.docs ?? [])
              .where((doc) => (doc.data() as Map<String, dynamic>)["isDeleted"] == true)
              .toList();

          if (deleted.isEmpty) {
            return const Center(
              child: Text("لا يوجد مدربون محذوفون", style: TextStyle(fontSize: 16)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: deleted.length,
            itemBuilder: (context, index) {
              final doc = deleted[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = (data["name"] ?? "").toString().trim();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ListTile(
                  leading: _teacherDeletedAvatar(data["profileImage"]),
                  title: Text(name.isNotEmpty ? name : "مدرب بدون اسم"),
                  subtitle: const Row(
                    children: [
                      Icon(Icons.cancel, color: Colors.red, size: 14),
                      SizedBox(width: 4),
                      Text(
                        "الحساب معطل (محذوف)",
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ],
                  ),
                  // Fixed width avoids the ListTile layout assertion that
                  // otherwise renders as a blank white screen (same fix as
                  // deleted_schools_screen.dart).
                  trailing: SizedBox(
                    width: 110,
                    child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () async {
                      await users.doc(doc.id).update({
                        "isDeleted": false,
                        "deletedAt": FieldValue.delete(),
                        "purgeAt": FieldValue.delete(),
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("تم استرجاع المدرب")),
                        );
                      }
                    },
                    icon: const Icon(Icons.restore, color: Colors.white, size: 16),
                    label: const Text("استعادة", style: TextStyle(color: Colors.white, fontSize: 12.5)),
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

Widget _teacherDeletedAvatar(String? profileImage) {
  if (profileImage != null && profileImage.isNotEmpty) {
    try {
      return CircleAvatar(backgroundImage: MemoryImage(base64Decode(profileImage)));
    } catch (_) {
      // Fall through to the default icon avatar below.
    }
  }
  return const CircleAvatar(
    backgroundColor: Colors.grey,
    child: Icon(Icons.person, color: Colors.white),
  );
}

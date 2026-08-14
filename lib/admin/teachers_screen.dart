import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../widgets/count_label.dart';

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

                var teachers = snapshot.data!.docs;

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

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Color(0xff1565C0),
                                  child: Icon(Icons.person, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    teacher["name"] ?? "",
                                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _detailLine(Icons.email, teacher["email"] ?? ""),
                            _detailLine(Icons.phone, teacher["phone"] ?? ""),
                            _detailLine(Icons.location_city, teacher["city"] ?? ""),
                            _detailLine(Icons.badge, teacher["licenseType"] ?? ""),
                            if ((teacher["schoolId"] ?? "").toString().isNotEmpty)
                              FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection("schools")
                                    .doc(teacher["schoolId"])
                                    .get(),
                                builder: (context, schoolSnap) {
                                  final schoolName = (schoolSnap.data?.data()
                                      as Map<String, dynamic>?)?["name"] ?? "";
                                  return _detailLine(Icons.school, schoolName);
                                },
                              ),
                            _detailLine(Icons.calendar_today, _formatDate(teacher["createdAt"])),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          teacher["isBlocked"] == true ? Colors.green : Colors.orange,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    onPressed: () async {
                                      final isBlocked = teacher["isBlocked"] == true;
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(isBlocked ? "تفعيل المدرب" : "تعطيل المدرب"),
                                          content: Text(
                                            isBlocked
                                                ? "هل أنت متأكد من تفعيل حساب ${teacher["name"] ?? ""}؟"
                                                : "هل أنت متأكد من تعطيل حساب ${teacher["name"] ?? ""}؟ لن يتمكن من تسجيل الدخول.",
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

                                      await users.doc(docId).update({
                                        "isBlocked": !isBlocked,
                                      });
                                    },
                                    icon: Icon(
                                      teacher["isBlocked"] == true ? Icons.check : Icons.block,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    label: Text(
                                      teacher["isBlocked"] == true ? "تفعيل" : "تعطيل",
                                      style: const TextStyle(color: Colors.white, fontSize: 13),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    onPressed: () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text("حذف المدرب"),
                                          content: Text(
                                            "هل أنت متأكد من حذف حساب ${teacher["name"] ?? ""} نهائيًا؟ هذا الإجراء لا يمكن التراجع عنه.",
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

                                      await FirebaseFirestore.instance
                                          .collection("users")
                                          .doc(docId)
                                          .delete();
                                    },
                                    icon: const Icon(Icons.delete, color: Colors.white, size: 16),
                                    label: const Text("حذف", style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: (teacher["isBlocked"] ?? false)
                                    ? Colors.red.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    (teacher["isBlocked"] ?? false) ? Icons.cancel : Icons.verified,
                                    color: (teacher["isBlocked"] ?? false) ? Colors.red : Colors.green,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    (teacher["isBlocked"] ?? false) ? "الحساب معطل" : "الحساب مفعل",
                                    style: TextStyle(
                                      color: (teacher["isBlocked"] ?? false) ? Colors.red : Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
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
}

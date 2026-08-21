import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/count_label.dart';
import '../services/app_helpers.dart';

class RegistrationRequestsScreen extends StatefulWidget {
  const RegistrationRequestsScreen({super.key});

  @override
  State<RegistrationRequestsScreen> createState() => _RegistrationRequestsScreenState();
}

class _RegistrationRequestsScreenState extends State<RegistrationRequestsScreen> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final requestsStream = FirebaseFirestore.instance
        .collection("teacher_requests")
        .where("status", isEqualTo: "pending")
        .where("emailVerified", isEqualTo: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: CountLabel(text: "طلبات تسجيل المدربين", stream: requestsStream),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
              stream: requestsStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var requests = snapshot.data!.docs;

                if (searchQuery.isNotEmpty) {
                  requests = requests.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data["teacherName"] ?? "").toString().toLowerCase();
                    final phone = (data["phone"] ?? "").toString().toLowerCase();
                    final email = (data["email"] ?? "").toString().toLowerCase();
                    return name.contains(searchQuery) || phone.contains(searchQuery) || email.contains(searchQuery);
                  }).toList();
                }

                if (requests.isEmpty) {
                  return const Center(child: Text("لا توجد طلبات"));
                }

                return ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    final data = request.data() as Map<String, dynamic>;

                    return Card(
                      margin: const EdgeInsets.all(10),
                      child: ListTile(
                        title: Text(data["teacherName"] ?? ""),
                        subtitle: Text(
                          "${data["phone"] ?? ""}${(data["licenseType"] ?? "").toString().isNotEmpty ? ' · ${data["licenseType"]}' : ''}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () async {
                                await FirebaseFirestore.instance
                                    .collection("users")
                                    .doc(data["teacherId"])
                                    .update({"isVerified": true});

                                await FirebaseFirestore.instance
                                    .collection("teacher_requests")
                                    .doc(request.id)
                                    .update({"status": "accepted"});

                                await sendNotification(
                                  userId: data["teacherId"],
                                  title: "تم قبول طلب تسجيلك",
                                  body: "مرحباً بك! يمكنك الآن تسجيل الدخول واستخدام التطبيق كمدرب.",
                                  type: "registration_approved",
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () async {
                                await FirebaseFirestore.instance
                                    .collection("teacher_requests")
                                    .doc(request.id)
                                    .update({"status": "rejected"});

                                await sendNotification(
                                  userId: data["teacherId"],
                                  title: "تم رفض طلب تسجيلك",
                                  body: "للأسف لم تتم الموافقة على طلب تسجيلك كمدرب. تواصل مع الإدارة لمزيد من المعلومات.",
                                  type: "registration_rejected",
                                );
                              },
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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LicenseTypesScreen extends StatefulWidget {
  const LicenseTypesScreen({super.key});

  @override
  State<LicenseTypesScreen> createState() => _LicenseTypesScreenState();
}

class _LicenseTypesScreenState extends State<LicenseTypesScreen> {

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  void showLicenseDialog({DocumentSnapshot? document}) {

    final TextEditingController controller =
    TextEditingController(
      text: document != null
          ? ((document.data() as Map<String, dynamic>?)?["name"] ?? "").toString()
          : "",
    );

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(
            document == null
                ? "إضافة نوع رخصة"
                : "تعديل نوع الرخصة",
          ),

          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: "اسم الرخصة",
            ),
          ),

          actions: [

            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("إلغاء"),
            ),

            ElevatedButton(
              onPressed: () async {

                if (controller.text.trim().isEmpty) return;

                if (document == null) {

                  await firestore
                      .collection("license_types")
                      .add({
                    "name": controller.text.trim(),
                    "createdAt": Timestamp.now(),
                    "isDeleted": false,
                  });

                } else {

                  await firestore
                      .collection("license_types")
                      .doc(document.id)
                      .update({
                    "name": controller.text.trim(),
                  });

                }

                Navigator.pop(context);

              },
              child: const Text("حفظ"),
            ),

          ],
        );
      },
    );
  }

  // Soft delete: the license type and everything stored inside its document
  // (and any subcollections/references to it elsewhere) stay untouched -
  // we just flag it as deleted and hide it from the main list, so it can
  // be fully restored later with all its data intact.
  Future<void> deleteLicense(String id) async {

    await firestore
        .collection("license_types")
        .doc(id)
        .update({
      "isDeleted": true,
      "deletedAt": Timestamp.now(),
    });

  }

  Future<void> restoreLicense(String id) async {
    await firestore
        .collection("license_types")
        .doc(id)
        .update({
      "isDeleted": false,
      "deletedAt": FieldValue.delete(),
    });
  }

  void _showDeletedLicenses() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _DeletedLicensesScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("أنواع الرخص"),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            tooltip: "الرخص المحذوفة",
            icon: const Icon(Icons.restore_from_trash),
            onPressed: _showDeletedLicenses,
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        onPressed: () {

          showLicenseDialog();

        },
        child: const Icon(Icons.add),
      ),

      body: StreamBuilder<QuerySnapshot>(

        stream: firestore
            .collection("license_types")
            .orderBy("createdAt")
            .snapshots(),

        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final licenses = snapshot.data!.docs
              .where((doc) => (doc.data() as Map<String, dynamic>)["isDeleted"] != true)
              .toList();

          if (licenses.isEmpty) {
            return const Center(
              child: Text(
                "لا يوجد أنواع رخص",
                style: TextStyle(fontSize: 18),
              ),
            );
          }

          return ListView.builder(

            itemCount: licenses.length,

            itemBuilder: (context, index) {

              final license = licenses[index];
              final licenseName = ((license.data() as Map<String, dynamic>)["name"] ?? "").toString();

              return Card(

                margin: const EdgeInsets.all(10),

                child: ListTile(

                  leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(
                      Icons.drive_eta,
                      color: Colors.white,
                    ),
                  ),

                  title: Text(
                    licenseName.isNotEmpty ? licenseName : "رخصة بدون اسم",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,

                    children: [

                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.orange,
                        ),
                        onPressed: () {

                          showLicenseDialog(
                            document: license,
                          );

                        },
                      ),

                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                        ),
                        onPressed: () async {

                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("حذف نوع الرخصة"),
                              content: Text(
                                "هل تريد حذف \"$licenseName\"؟ يمكنك استعادتها لاحقاً من قائمة المحذوفات.",
                              ),
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

                          if (confirmed != true) return;

                          await deleteLicense(license.id);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("تم الحذف، يمكنك استعادته من قائمة المحذوفات")),
                            );
                          }

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
    );
  }
}

class _DeletedLicensesScreen extends StatelessWidget {
  const _DeletedLicensesScreen();

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    Future<void> restore(String id) async {
      await firestore.collection("license_types").doc(id).update({
        "isDeleted": false,
        "deletedAt": FieldValue.delete(),
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("أنواع الرخص المحذوفة"),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection("license_types")
            .where("isDeleted", isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("حدث خطأ: ${snapshot.error}"));
          }

          final deleted = snapshot.data?.docs ?? [];

          if (deleted.isEmpty) {
            return const Center(
              child: Text("لا يوجد أنواع رخص محذوفة", style: TextStyle(fontSize: 16)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: deleted.length,
            itemBuilder: (context, index) {
              final doc = deleted[index];
              final licenseData = doc.data() as Map<String, dynamic>;
              final licenseName = (licenseData["name"] ?? "").toString().trim();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.drive_eta, color: Colors.white),
                  ),
                  title: Text(licenseName.isNotEmpty ? licenseName : "رخصة بدون اسم"),
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
                        await restore(doc.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("تم استرجاع نوع الرخصة وكل بياناته")),
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

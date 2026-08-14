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
      text: document != null ? document["name"] : "",
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

  Future<void> deleteLicense(String id) async {

    await firestore
        .collection("license_types")
        .doc(id)
        .delete();

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("أنواع الرخص"),
        backgroundColor: Colors.blue,
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

          final licenses = snapshot.data!.docs;

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
                    license["name"],
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
                        onPressed: () {

                          deleteLicense(license.id);

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

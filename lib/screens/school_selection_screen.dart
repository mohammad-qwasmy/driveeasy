import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'license_type_screen.dart';

/// First step for a student starting (or adding) a teacher relationship:
/// pick a driving school. Only teachers belonging to the chosen school will
/// be shown afterward.
class SchoolSelectionScreen extends StatefulWidget {
  const SchoolSelectionScreen({super.key});

  @override
  State<SchoolSelectionScreen> createState() => _SchoolSelectionScreenState();
}

class _SchoolSelectionScreenState extends State<SchoolSelectionScreen> {
  String? selectedSchoolId;
  String? selectedSchoolName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("اختر المدرسة"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("schools").orderBy("createdAt").snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final schools = snapshot.data!.docs;

          if (schools.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text("لا يوجد مدارس مسجلة بعد بالنظام", textAlign: TextAlign.center),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  "اختر المدرسة حتى نعرض لك المدربين المنتمين إليها",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: schools.length,
                    itemBuilder: (context, index) {
                      final school = schools[index];
                      final name = (school.data() as Map<String, dynamic>)["name"] ?? "";
                      final selected = selectedSchoolId == school.id;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(
                            color: selected ? Colors.blue : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.school)),
                          title: Text(name),
                          trailing: selected
                              ? const Icon(Icons.check_circle, color: Colors.blue)
                              : const Icon(Icons.circle_outlined),
                          onTap: () => setState(() {
                            selectedSchoolId = school.id;
                            selectedSchoolName = name;
                          }),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: selectedSchoolId == null
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LicenseTypeScreen(
                                  schoolId: selectedSchoolId!,
                                  schoolName: selectedSchoolName!,
                                ),
                              ),
                            );
                          },
                    child: const Text("التالي", style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

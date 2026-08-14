import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/app_helpers.dart';

/// Lets a teacher fully control one student's learning plan: add as many
/// steps as they want, name them however fits their own teaching method,
/// remove steps, and mark each done/not-done. The student sees the same
/// list (read-only) on their own "خطتي" screen, with a real-time
/// notification whenever a step is completed.
class StudentPlanScreen extends StatefulWidget {
  final String linkId;
  final String studentId;
  final String studentName;

  const StudentPlanScreen({
    super.key,
    required this.linkId,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentPlanScreen> createState() => _StudentPlanScreenState();
}

class _StudentPlanScreenState extends State<StudentPlanScreen> {
  List<Map<String, dynamic>> steps = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await ensureStudentPlan(widget.linkId);
    if (!mounted) return;
    setState(() {
      steps = loaded;
      isLoading = false;
    });
  }

  Future<void> _persist() async {
    await FirebaseFirestore.instance
        .collection("student_plans")
        .doc(widget.linkId)
        .set({"planId": widget.linkId, "studentId": widget.studentId, "steps": steps});
  }

  Future<void> _toggle(int index, bool value) async {
    setState(() => steps[index]["done"] = value);
    await _persist();

    if (value) {
      await sendNotification(
        userId: widget.studentId,
        title: "تقدم جديد في خطتك",
        body: "أنجزت خطوة: ${steps[index]["title"]}",
        type: "plan_update",
      );
    }
  }

  Future<void> _addStep() async {
    final controller = TextEditingController();

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("إضافة نقطة جديدة للخطة"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "مثال: التدرب على الركن الموازي",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("إضافة"),
          ),
        ],
      ),
    );

    if (title == null || title.isEmpty) return;

    setState(() {
      steps.add({
        "id": "s${DateTime.now().millisecondsSinceEpoch}",
        "title": title,
        "done": false,
      });
    });

    await _persist();
  }

  Future<void> _removeStep(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف النقطة"),
        content: Text("هل تريد حذف \"${steps[index]["title"]}\" من الخطة؟"),
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

    setState(() => steps.removeAt(index));
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final done = steps.where((s) => s["done"] == true).length;
    final percent = steps.isEmpty ? 0.0 : done / steps.length;

    return Scaffold(
      appBar: AppBar(title: Text("خطة ${widget.studentName}"), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStep,
        icon: const Icon(Icons.add),
        label: const Text("إضافة نقطة"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: LinearProgressIndicator(value: percent, minHeight: 12),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "${(percent * 100).round()}% مكتمل ($done من ${steps.length})",
                            style: const TextStyle(
                              color: Color(0xff1565C0),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: steps.isEmpty
                        ? const Center(
                            child: Text(
                              "لا يوجد نقاط بعد — اضغط \"إضافة نقطة\" لبناء خطة هذا الطالب",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: steps.length,
                            itemBuilder: (context, index) {
                              final step = steps[index];
                              final isDone = step["done"] == true;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: SwitchListTile(
                                  value: isDone,
                                  onChanged: (value) => _toggle(index, value),
                                  activeColor: Colors.green,
                                  title: Text(
                                    step["title"] ?? "",
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(isDone ? "منجزة" : "لم تنجز بعد"),
                                  secondary: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => _removeStep(index),
                                  ),
                                ),
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

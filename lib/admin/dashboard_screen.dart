import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

import 'widgets/custom_app_bar.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/dashboard_stats.dart';
import 'widgets/dashboard_action_button.dart';
import 'admin_management_screen.dart';
import 'services/admin_service.dart';
import '../screens/profile_screen.dart';
import '../services/app_language.dart';
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  final AdminService adminService = AdminService();

  int studentsCount = 0;
  int teachersCount = 0;
  int requestsCount = 0;
  int adminsCount = 0;
  String adminName = "";

  @override
  void initState() {
    super.initState();
    loadStudentsCount();
    loadAdminName();
  }

  Future<void> loadAdminName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection("users").doc(user.uid).get();
    final data = doc.data();
    if (!mounted || data == null) return;

    setState(() => adminName = data["name"] ?? "");
  }

  Future<void> loadStudentsCount() async {
    studentsCount = await adminService.getStudentsCount();
    teachersCount = await adminService.getTeachersCount();
    requestsCount = await adminService.getPendingRequestsCount();
    adminsCount = await adminService.getAdminsCount();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: CustomAdminAppBar(
        title: tr("admin_dashboard_title"),
        showBack: false,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [

              DashboardHeader(
                name: adminName,
                greeting: tr("welcome"),
                subtitle: tr("admin_dashboard_title"),
              ),

              const SizedBox(height: 25),

              Row(
                children:  [

                  DashboardStats(
                    icon: Icons.people,
                    title: tr("requests"),
                    value: requestsCount.toString(),
                    color: Colors.blue,
                  ),

                  SizedBox(width: 12),

                  DashboardStats(
                    icon: Icons.school,
                    title: tr("teachers"),
                    value: teachersCount.toString(),
                    color: Colors.green,
                  ),

                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [

                  DashboardStats(
                    icon: Icons.admin_panel_settings,
                    title: tr("admins"),
                    value: adminsCount.toString(),
                    color: Colors.orange,
                  ),

                  SizedBox(width: 12),

                  DashboardStats(
                    icon: Icons.people,
                    title: tr("students"),
                    value: studentsCount.toString(),
                    color: Colors.blue,
                  ),

                ],
              ),

              const SizedBox(height: 25),
              DashboardActionButton(
                title: tr("open_admin_management"),
                icon: Icons.dashboard_customize,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const AdminManagementScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),
              DashboardActionButton(
                title: tr("my_profile"),
                icon: Icons.person,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfileScreen(),
                    ),
                  );
                },
              ),

            ],
          ),
        ),
      ),
    );
  }
}
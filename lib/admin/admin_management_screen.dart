import 'package:flutter/material.dart';

import 'widgets/custom_app_bar.dart';
import 'widgets/admin_button.dart';
import 'registration_requests_screen.dart';
import 'teachers_screen.dart';
import 'license_types_screen.dart';
import 'schools_screen.dart';
import 'students_screen.dart';
import '../services/app_language.dart';
import 'super_admins_screen.dart';

class AdminManagementScreen extends StatelessWidget {
  const AdminManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F7FA),

      appBar: CustomAdminAppBar(
        title: tr("admin_management_title"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(18),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Text(
              tr("manage_app_title"),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              tr("choose_section_subtitle"),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 25),

            Expanded(
              child: ListView(

                children: [

                  AdminButton(
                    icon: Icons.assignment,
                    title: tr("registration_requests"),
                    subtitle: tr("registration_requests_sub"),
                    color: Colors.orange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegistrationRequestsScreen(),
                        ),
                      );
                    },
                  ),

                  AdminButton(
                    icon: Icons.school,
                    title: tr("teachers"),
                    subtitle: tr("manage_teachers_sub"),
                    color: Colors.green,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TeachersScreen(),
                        ),
                      );
                    },
                  ),

                  AdminButton(
                    icon: Icons.directions_car,
                    title: tr("license_types"),
                    subtitle: tr("manage_license_types_sub"),
                    color: Colors.deepPurple,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LicenseTypesScreen(),
                        ),
                      );
                    },
                  ),

                  AdminButton(
                    icon: Icons.school,
                    title: tr("schools"),
                    subtitle: tr("manage_schools_sub"),
                    color: Colors.teal,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SchoolsScreen(),
                        ),
                      );
                    },
                  ),

                  AdminButton(
                    icon: Icons.groups,
                    title: tr("students"),
                    subtitle: tr("manage_students_sub"),
                    color: Colors.indigo,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminStudentsScreen(),
                        ),
                      );
                    },
                  ),

                  AdminButton(
                    icon: Icons.admin_panel_settings,
                    title: tr("super_admins"),
                    subtitle: tr("manage_super_admins_sub"),
                    color: Colors.red,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SuperAdminsScreen(),
                        ),
                      );
                    },
                  ),

                ],
              ),
            ),

          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';

class DashboardHeader extends StatelessWidget {
  final String name;
  final String? greeting;
  final String? subtitle;

  const DashboardHeader({
    super.key,
    required this.name,
    this.greeting,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "👋 ${greeting ?? "Welcome"}, $name",
          style: AppTextStyles.pageTitle,
        ),

        const SizedBox(height: 6),

        Text(
          subtitle ?? "Super Admin Dashboard",
          style: AppTextStyles.body,
        ),
      ],
    );
  }
}
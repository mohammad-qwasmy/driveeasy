import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';

class DashboardStats extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const DashboardStats({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 130,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withOpacity(.15),
              child: Icon(icon, color: color, size: 22),
            ),

            const SizedBox(height: 8),

            Text(
              value,
              style: AppTextStyles.number,
            ),

            const SizedBox(height: 4),

            Text(
              title,
              style: AppTextStyles.cardTitle,
            ),
          ],
        ),
      ),
    );
  }
}
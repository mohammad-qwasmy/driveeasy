import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Support WhatsApp number, international format, no leading "+" or
/// spaces/dashes (wa.me requires this exact format). Update this single
/// constant to change the support number app-wide.
const String supportWhatsAppNumber = "972584960013"; // Mohammad's WhatsApp number

Future<void> openWhatsAppSupport({String? prefilledMessage}) async {
  final text = Uri.encodeComponent(prefilledMessage ?? "مرحباً، بحاجة للمساعدة بخصوص تطبيق DriveEasy.");
  final uri = Uri.parse("https://wa.me/$supportWhatsAppNumber?text=$text");
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Shown when a user who previously deleted their own account (soft-delete,
/// 30-day recovery window) signs back in. Lets them restore everything
/// instantly themselves, or reach support via WhatsApp. Returns true if the
/// account was restored (caller should then continue into the app), false
/// if the user backed out (caller should sign them out).
Future<bool> showAccountRestoreDialog({
  required BuildContext context,
  required String uid,
  required DateTime deletedAt,
  required DateTime purgeAt,
}) async {
  final daysLeft = purgeAt.difference(DateTime.now()).inDays;

  final restored = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.restore_from_trash, color: Colors.orange, size: 26),
          SizedBox(width: 8),
          Expanded(child: Text("حسابك محذوف مؤقتاً")),
        ],
      ),
      content: Text(
        "قمت بحذف هذا الحساب مسبقاً. بياناتك لا تزال محفوظة، ويمكنك استرجاع حسابك الآن خلال "
        "${daysLeft > 0 ? daysLeft : 0} يوم متبقٍ قبل حذفها نهائياً وبشكل لا رجعة فيه.",
        style: const TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await openWhatsAppSupport(
              prefilledMessage: "مرحباً، بدي أتواصل بخصوص حسابي المحذوف بتطبيق DriveEasy.",
            );
          },
          child: const Text("تواصل معنا"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text("إلغاء"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("استرجاع حسابي"),
        ),
      ],
    ),
  );

  if (restored == true) {
    await FirebaseFirestore.instance.collection("users").doc(uid).update({
      "isDeleted": false,
      "deletedAt": FieldValue.delete(),
      "purgeAt": FieldValue.delete(),
    });
    return true;
  }

  return false;
}

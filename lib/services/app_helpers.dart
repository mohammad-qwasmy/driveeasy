import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared helpers used across the student/teacher screens: date handling,
/// notifications, and the default driving-lesson curriculum used for the
/// student progress plan.

const List<String> arabicWeekOrder = [
  "السبت",
  "الأحد",
  "الاثنين",
  "الثلاثاء",
  "الأربعاء",
  "الخميس",
  "الجمعة",
];

/// Dart's DateTime.weekday: Monday=1 ... Sunday=7.
/// Maps that to the Arabic week order used across the app (week starts Saturday).
String weekdayNameFromDate(DateTime date) {
  const map = {
    DateTime.saturday: "السبت",
    DateTime.sunday: "الأحد",
    DateTime.monday: "الاثنين",
    DateTime.tuesday: "الثلاثاء",
    DateTime.wednesday: "الأربعاء",
    DateTime.thursday: "الخميس",
    DateTime.friday: "الجمعة",
  };
  return map[date.weekday]!;
}

String isoDate(DateTime date) {
  return "${date.year.toString().padLeft(4, '0')}-"
      "${date.month.toString().padLeft(2, '0')}-"
      "${date.day.toString().padLeft(2, '0')}";
}

String todayIso() => isoDate(DateTime.now());

const List<String> _arabicMonths = [
  "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
  "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
];

/// Formats an ISO date (yyyy-MM-dd) as e.g. "الثلاثاء 14 يوليو 2026".
String formatIsoDateArabic(String iso) {
  try {
    final date = DateTime.parse(iso);
    final weekday = weekdayNameFromDate(date);
    final month = _arabicMonths[date.month - 1];
    return "$weekday ${date.day} $month ${date.year}";
  } catch (_) {
    return iso;
  }
}

/// Returns the next real calendar date (as DateTime) that falls on
/// [arabicDayName], counting today as a possible match, offset by
/// [weeksAhead] extra weeks (0 = the soonest occurrence).
DateTime nextDateForArabicWeekday(String arabicDayName, {int weeksAhead = 0}) {
  final targetIndex = arabicWeekOrder.indexOf(arabicDayName);
  if (targetIndex == -1) return DateTime.now();

  final now = DateTime.now();
  final todayArabicIndex = arabicWeekOrder.indexOf(weekdayNameFromDate(now));

  int daysUntil = (targetIndex - todayArabicIndex) % 7;
  if (daysUntil < 0) daysUntil += 7;

  return DateTime(now.year, now.month, now.day)
      .add(Duration(days: daysUntil + (weeksAhead * 7)));
}

/// Writes a real, persisted in-app notification for [userId].
Future<void> sendNotification({
  required String userId,
  required String title,
  required String body,
  String type = "general",
}) async {
  await FirebaseFirestore.instance.collection("notifications").add({
    "userId": userId,
    "title": title,
    "body": body,
    "type": type,
    "read": false,
    "createdAt": Timestamp.now(),
  });
}

/// Parses a booking's date + time-range ("08:00 - 08:40") into the real
/// end DateTime, so the app can tell whether a lesson has actually passed
/// (not just whether the calendar day has passed).
DateTime? parseBookingEndDateTime(String date, String timeRange) {
  try {
    final parts = timeRange.split("-");
    final endStr = parts.length > 1 ? parts[1].trim() : parts[0].trim();
    final dateParts = date.split("-");
    final timeParts = endStr.split(":");
    return DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
  } catch (_) {
    return null;
  }
}

/// True once a slot's own start time (today only) has already passed —
/// used to hide available slots for today that are no longer bookable.
bool isSlotPast(String date, String startTime, {DateTime? now}) {
  final current = now ?? DateTime.now();
  if (date != isoDate(current)) return date.compareTo(isoDate(current)) < 0;
  try {
    final parts = startTime.split(":");
    final slotTime = DateTime(current.year, current.month, current.day,
        int.parse(parts[0]), int.parse(parts[1]));
    return current.isAfter(slotTime);
  } catch (_) {
    return false;
  }
}

/// True once a booking's real end date/time is in the past. Used to hide
/// lessons from "الدرس القادم" and "مواعيدي" the moment they're actually
/// over, not just once the calendar day changes.
bool isBookingPast(String date, String timeRange, {DateTime? now}) {
  final end = parseBookingEndDateTime(date, timeRange);
  if (end == null) return false;
  return (now ?? DateTime.now()).isAfter(end);
}

/// Formats an ISO date + "HH:mm" time together, e.g.
/// "الثلاثاء 14 يوليو 2026 - 05:30 م".
String formatIsoDateTimeArabic(String iso, String time) {
  final datePart = formatIsoDateArabic(iso);
  if (time.isEmpty) return datePart;

  try {
    final parts = time.split(":");
    int hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? "م" : "ص";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return "$datePart - $hour:$minute $period";
  } catch (_) {
    return "$datePart - $time";
  }
}

/// The fixed curriculum every student progresses through, based on the
/// official driving-instructor stage/chapter chart (التأهل / التمكن /
/// مهارات سياقة متقدمة / التطبيق). Kept as one flat, ordered list; the
/// teacher can still freely add or remove points on top of this.
const List<Map<String, String>> defaultPlanSteps = [
  // المرحلة (١) التأهل — الفصل (أ)
  {"id": "s1", "title": "الدخول للمركبة والخروج منها"},
  {"id": "s2", "title": "أجهزة التشغيل"},
  {"id": "s3", "title": "أجهزة الأمان"},
  {"id": "s4", "title": "أجهزة المراقبة والمعلومات"},
  {"id": "s5", "title": "الجلوس الصحيح وعمليات التحضير للسفر"},
  {"id": "s6", "title": "تشغيل المحرك"},
  {"id": "s7", "title": "بداية السفر والتسارع"},
  {"id": "s8", "title": "تخفيف السرعة والوقوف"},
  {"id": "s9", "title": "تأمين المركبة وإيقاف عمل المحرك عند الانتهاء من السفر"},
  // الفصل (ب)
  {"id": "s10", "title": "توجيه المقود بخط مستقيم"},
  {"id": "s11", "title": "توجيه المقود بالمنعطفات"},
  {"id": "s12", "title": "استخدام يدوي لليد الغيارات الأتوماتيكية"},
  // الفصل (ج)
  {"id": "s13", "title": "السفر بسرعة منخفضة بمساعدة الفرامل"},
  {"id": "s14", "title": "الوقوف لهدف أثناء السفر للأمام"},
  {"id": "s15", "title": "بداية السفر بمنحدر شديد"},
  {"id": "s16", "title": "بداية السفر بصعود شديد"},
  {"id": "s17", "title": "السفر للخلف بخط مستقيم"},
  // الفصل (أ) — بناء مهارة القيادة / التطبيق
  {"id": "s18", "title": "عادات النظر الصحيحة"},
  {"id": "s19", "title": "السفر بيمين الشارع"},
  {"id": "s20", "title": "تغيير مسالك"},
  {"id": "s21", "title": "الوقوف والتوقف بيمين الشارع أو بيسارها"},
  // الفصل (ب)
  {"id": "s22", "title": "الاقتراب من المفترقات - التموقع والعبور"},
  {"id": "s23", "title": "الانعطاف لليمين"},
  {"id": "s24", "title": "الانعطاف لليسار"},
  {"id": "s25", "title": "الانعطاف حدوة حصان"},
  // الفصل (ج)
  {"id": "s26", "title": "الوقوف لهدف بالسفر للخلف"},
  {"id": "s27", "title": "توجيه المركبة بالسفر للخلف"},
  {"id": "s28", "title": "الوقوف بين المركبات بالسفر للخلف باليمين وباليسار"},
  {"id": "s29", "title": "الخروج من مكان مغلق"},
  // المرحلة (٢) التمكن — الفصل (أ)
  {"id": "s30", "title": "سرعة السفر"},
  {"id": "s31", "title": "المحافظة على مسافة"},
  {"id": "s32", "title": "تصرفات سائق مركبة متجاوزة"},
  {"id": "s33", "title": "تجاوز مركبة مسافرة"},
  // الفصل (ب)
  {"id": "s34", "title": "إعطاء حق الأولوية بالطريق (ليس بالمفترق)"},
  {"id": "s35", "title": "إعطاء حق الأولوية بمفترق خالٍ من الإشارات"},
  {"id": "s36", "title": "إعطاء حق الأولوية بمفترق يحتوي على إشارات"},
  {"id": "s37", "title": "إعطاء حق الأولوية بمفترق يحتوي على إشارات ضوئية"},
  {"id": "s38", "title": "ملائمة السفر مع المشاة"},
  {"id": "s39", "title": "التوقف حسب العلامات التي على سطح الطريق"},
  // المرحلة (٣) مهارات سياقة متقدمة — الفصل (أ)
  {"id": "s40", "title": "السفر بطرق ليست بلدية بسرعة عالية"},
  {"id": "s41", "title": "أمور لا بد من القيام بها في حالة خطر مفاجئ"},
  {"id": "s42", "title": "نزول مخطط لهامش الطريق والرجوع للشارع"},
  {"id": "s43", "title": "نزول مفاجئ لهامش الطريق والرجوع للشارع"},
  {"id": "s44", "title": "السياقة بطرق جبلية - ضيقة وملتوية"},
  // الفصل (ب)
  {"id": "s45", "title": "الامتناع عن التزحلق وطرق الخروج منها"},
  {"id": "s46", "title": "التطرق لمركبات الأمن"},
  {"id": "s47", "title": "التصرف بملتقى سكة حديد"},
  {"id": "s48", "title": "السياقة وقت الإضاءة"},
];


/// Makes sure a learning plan exists for [planKey] — normally the id of a
/// specific student↔teacher link (a student can have more than one teacher,
/// one per license type, so the plan is scoped per relationship, not just
/// per student). Creates the default curriculum the first time it's
/// accessed. Returns the up-to-date steps list.
Future<List<Map<String, dynamic>>> ensureStudentPlan(String planKey) async {
  final ref =
      FirebaseFirestore.instance.collection("student_plans").doc(planKey);
  final snap = await ref.get();

  if (!snap.exists) {
    final steps = defaultPlanSteps
        .map((s) => {"id": s["id"], "title": s["title"], "done": false})
        .toList();
    await ref.set({"planId": planKey, "steps": steps});
    return steps;
  }

  final data = snap.data() as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data["steps"] ?? []);
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Very small, dependency-free-ish i18n layer: a global notifier holding the
/// current language code ("ar" | "en" | "he"), persisted locally (so it
/// works even before login) and mirrored to the user's Firestore profile
/// once they're signed in. `tr()` looks a key up in [_strings] below.
///
/// Scope note: this covers the app's main navigation and chrome (login,
/// register, home, teacher dashboard, profile). Screen content that's the
/// user's own data (chat messages, plan steps a teacher types, etc.) is
/// naturally left as-is since it's not UI text.
class AppLanguage {
  static final ValueNotifier<String> code = ValueNotifier<String>("ar");

  static const Map<String, Locale> locales = {
    "ar": Locale("ar"),
    "en": Locale("en"),
    "he": Locale("he"),
  };

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString("app_language");
      if (saved != null && locales.containsKey(saved)) {
        code.value = saved;
      }
    } catch (_) {
      // SharedPreferences unavailable — fall back to default "ar".
    }
  }

  static Future<void> setLanguage(String newCode) async {
    if (!locales.containsKey(newCode)) return;
    code.value = newCode;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("app_language", newCode);
    } catch (_) {}

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .update({"language": newCode});
      } catch (_) {}
    }
  }

  static Locale get currentLocale => locales[code.value] ?? const Locale("ar");
}

/// Translation lookup: tr("key") returns the string in the active language,
/// falling back to Arabic then to the key itself if missing.
String tr(String key) {
  final lang = AppLanguage.code.value;
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[lang] ?? entry["ar"] ?? key;
}

const Map<String, Map<String, String>> _strings = {
  "app_name": {"ar": "DriveEasy", "en": "DriveEasy", "he": "DriveEasy"},
  "welcome_back": {"ar": "أهلاً بك", "en": "Welcome", "he": "ברוכים הבאים"},
  "email": {"ar": "البريد الإلكتروني", "en": "Email", "he": "אימייל"},
  "password": {"ar": "كلمة المرور", "en": "Password", "he": "סיסמה"},
  "login": {"ar": "تسجيل الدخول", "en": "Log in", "he": "התחברות"},
  "create_account": {"ar": "إنشاء حساب جديد", "en": "Create a new account", "he": "יצירת חשבון חדש"},
  "forgot_password": {"ar": "نسيت كلمة المرور؟", "en": "Forgot password?", "he": "שכחת סיסמה?"},
  "remember_me": {"ar": "تذكرني", "en": "Remember me", "he": "זכור אותי"},

  "create_account_title": {"ar": "إنشاء حساب", "en": "Create Account", "he": "יצירת חשבון"},
  "full_name": {"ar": "الاسم الكامل", "en": "Full name", "he": "שם מלא"},
  "phone": {"ar": "رقم الهاتف", "en": "Phone number", "he": "מספר טלפון"},
  "confirm_password": {"ar": "تأكيد كلمة المرور", "en": "Confirm password", "he": "אימות סיסמה"},
  "account_type": {"ar": "نوع الحساب", "en": "Account type", "he": "סוג חשבון"},
  "student": {"ar": "طالب", "en": "Student", "he": "תלמיד"},
  "teacher": {"ar": "مدرب", "en": "Teacher", "he": "מדריך"},
  "license_type_teaching": {"ar": "نوع الرخصة التي ستقوم بتدريسها", "en": "License type you'll teach", "he": "סוג הרישיון שתלמד"},

  "home_next_lesson": {"ar": "الدرس القادم", "en": "Next lesson", "he": "השיעור הבא"},
  "home_progress": {"ar": "نسبة التقدم", "en": "Progress", "he": "התקדמות"},
  "home_quick_services": {"ar": "الخدمات السريعة", "en": "Quick services", "he": "שירותים מהירים"},
  "book_lesson": {"ar": "حجز درس", "en": "Book a lesson", "he": "הזמנת שיעור"},
  "my_bookings": {"ar": "مواعيدي", "en": "My bookings", "he": "התורים שלי"},
  "my_plan": {"ar": "خطتي", "en": "My plan", "he": "התוכנית שלי"},
  "my_lessons": {"ar": "دروسي", "en": "My lessons", "he": "השיעורים שלי"},
  "chat_with_teacher": {"ar": "محادثة مع المدرب", "en": "Chat with teacher", "he": "צ'אט עם המדריך"},
  "teacher_link": {"ar": "اختيار مدرب", "en": "Choose a teacher", "he": "בחירת מדריך"},
  "my_account": {"ar": "حسابي", "en": "My account", "he": "החשבון שלי"},

  "teacher_dashboard_title": {"ar": "لوحة تحكم المدرب", "en": "Teacher dashboard", "he": "לוח בקרה למדריך"},
  "my_schedule": {"ar": "جدول عملي", "en": "My schedule", "he": "לוח הזמנים שלי"},
  "my_calendar": {"ar": "جدولي", "en": "My calendar", "he": "היומן שלי"},
  "link_requests": {"ar": "طلبات التسجيل", "en": "Registration requests", "he": "בקשות רישום"},
  "booking_requests": {"ar": "طلبات الحجز", "en": "Booking requests", "he": "בקשות הזמנה"},
  "my_students": {"ar": "طلابي", "en": "My students", "he": "התלמידים שלי"},
  "my_profile": {"ar": "الملف الشخصي", "en": "My profile", "he": "הפרופיל שלי"},

  "edit_info": {"ar": "تعديل البيانات", "en": "Edit info", "he": "עריכת פרטים"},
  "change_password": {"ar": "تغيير كلمة المرور", "en": "Change password", "he": "שינוי סיסמה"},
  "logout": {"ar": "تسجيل الخروج", "en": "Log out", "he": "התנתקות"},
  "city": {"ar": "المدينة", "en": "City", "he": "עיר"},
  "license_type": {"ar": "نوع الرخصة", "en": "License type", "he": "סוג רישיון"},
  "lessons_count": {"ar": "عدد الدروس", "en": "Lessons", "he": "מספר שיעורים"},
  "rating": {"ar": "التقييم", "en": "Rating", "he": "דירוג"},
  "bookings": {"ar": "الحجوزات", "en": "Bookings", "he": "הזמנות"},
  "language": {"ar": "اللغة", "en": "Language", "he": "שפה"},
  "choose_language": {"ar": "اختر اللغة", "en": "Choose language", "he": "בחר שפה"},
  "profile_title": {"ar": "الملف الشخصي", "en": "Profile", "he": "פרופיל"},
  "not_available": {"ar": "غير متوفر", "en": "Not available", "he": "לא זמין"},
  "choose_photo": {"ar": "اختيار صورة", "en": "Choose photo", "he": "בחירת תמונה"},

  "admin": {"ar": "أدمن", "en": "Admin", "he": "מנהל"},
  "super_admin": {"ar": "سوبر أدمن", "en": "Super Admin", "he": "מנהל-על"},

  "welcome": {"ar": "مرحبًا", "en": "Welcome", "he": "ברוך הבא"},
  "admin_dashboard_title": {"ar": "لوحة تحكم الأدمن", "en": "Admin Dashboard", "he": "לוח בקרת מנהל"},
  "requests": {"ar": "الطلبات", "en": "Requests", "he": "בקשות"},
  "teachers": {"ar": "المدربون", "en": "Teachers", "he": "מדריכים"},
  "admins": {"ar": "الأدمن", "en": "Admins", "he": "מנהלים"},
  "students": {"ar": "الطلاب", "en": "Students", "he": "תלמידים"},
  "open_admin_management": {"ar": "فتح إدارة الأدمن", "en": "Open Admin Management", "he": "פתיחת ניהול מנהלים"},

  "admin_management_title": {"ar": "إدارة الأدمن", "en": "Admin Management", "he": "ניהול מנהלים"},
  "manage_app_title": {"ar": "إدارة التطبيق", "en": "Manage Your Application", "he": "ניהול האפליקציה"},
  "choose_section_subtitle": {"ar": "اختر القسم الذي تريد إدارته", "en": "Choose the section you want to manage.", "he": "בחר את המקטע שברצונך לנהל."},
  "registration_requests": {"ar": "طلبات التسجيل", "en": "Registration Requests", "he": "בקשות הרשמה"},
  "registration_requests_sub": {"ar": "الموافقة على الطلبات أو رفضها", "en": "Approve or reject requests", "he": "אישור או דחיית בקשות"},
  "manage_teachers_sub": {"ar": "إدارة جميع المدربين", "en": "Manage all teachers", "he": "ניהול כל המדריכים"},
  "license_types": {"ar": "أنواع الرخص", "en": "License Types", "he": "סוגי רישיון"},
  "manage_license_types_sub": {"ar": "إدارة أنواع رخص القيادة", "en": "Manage driving license types", "he": "ניהול סוגי רישיון נהיגה"},
  "schools": {"ar": "المدارس", "en": "Schools", "he": "בתי ספר"},
  "manage_schools_sub": {"ar": "إنشاء وإدارة مدارس القيادة", "en": "Create and manage driving schools", "he": "יצירה וניהול בתי ספר לנהיגה"},
  "super_admins": {"ar": "حسابات الأدمن", "en": "Admin Accounts", "he": "חשבונות מנהל"},
  "manage_super_admins_sub": {"ar": "إنشاء وإدارة حسابات الأدمن والسوبر أدمن", "en": "Create and manage admin & super admin accounts", "he": "יצירה וניהול חשבונות מנהל ומנהל-על"},
  "logout_sub": {"ar": "تسجيل الخروج من التطبيق", "en": "Sign out from the application", "he": "התנתקות מהאפליקציה"},
  "profile_sub": {"ar": "بياناتك الشخصية وإعدادات اللغة", "en": "Your personal info and language settings", "he": "הפרטים האישיים והגדרות השפה שלך"},

  "super_admin_dashboard_title": {"ar": "لوحة تحكم الأدمن", "en": "Admin Dashboard", "he": "לוח בקרת מנהל"},
  "manage_students": {"ar": "إدارة الطلاب", "en": "Manage Students", "he": "ניהול תלמידים"},
  "manage_teachers": {"ar": "إدارة المدربين", "en": "Manage Teachers", "he": "ניהול מדריכים"},
  "manage_bookings": {"ar": "إدارة الحجوزات", "en": "Manage Bookings", "he": "ניהול הזמנות"},
  "statistics": {"ar": "الإحصائيات", "en": "Statistics", "he": "סטטיסטיקות"},
  "settings": {"ar": "الإعدادات", "en": "Settings", "he": "הגדרות"},
};

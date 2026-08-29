import 'package:flutter/material.dart';

class BookingDetailsScreen extends StatelessWidget {
final Map<String, dynamic> booking;

const BookingDetailsScreen({
super.key,
required this.booking,
});

Color getStatusColor(String status) {
switch (status) {
case "accepted":
return Colors.green;

case "pending":
return Colors.orange;

case "rejected":
return Colors.red;

case "completed":
return Colors.blue;

case "teacherProposed":
return const Color(0xff1565C0);

default:
return Colors.grey;
}
}

String getStatusText(String status) {
switch (status) {
case "accepted":
return "مقبول";

case "pending":
return "قيد الانتظار";

case "rejected":
return "مرفوض";

case "completed":
return "مكتمل";

case "teacherProposed":
return "مقترح من المدرب";

default:
return status;
}
}

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: const Text("تفاصيل الحجز"),
centerTitle: true,
),

body: SingleChildScrollView(
padding: const EdgeInsets.all(20),

child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,

children: [

const CircleAvatar(
radius: 45,
backgroundColor: Colors.blue,
child: Icon(
Icons.person,
color: Colors.white,
size: 50,
),
),

const SizedBox(height: 20),

Center(
child: Text(
booking["teacherName"],
style: const TextStyle(
fontSize: 24,
fontWeight: FontWeight.bold,
),
),
),

const SizedBox(height: 30),

Card(
elevation: 3,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(18),
),

child: Padding(
padding: const EdgeInsets.all(18),

child: Column(
children: [
ListTile(
leading: const Icon(
Icons.calendar_month,
color: Colors.blue,
),
title: const Text("اليوم"),
subtitle: Text(booking["day"]),
),

const Divider(),

ListTile(
leading: const Icon(
Icons.access_time,
color: Colors.orange,
),
title: const Text("الوقت"),
subtitle: Text(booking["time"]),
),

const Divider(),

ListTile(
leading: const Icon(
Icons.attach_money,
color: Colors.green,
),
title: const Text("السعر"),
subtitle: Text("${booking["price"]} ₪"),
),

const Divider(),

ListTile(
leading: Icon(
Icons.info,
color: getStatusColor(
booking["status"],
),
),
title: const Text("حالة الحجز"),
subtitle: Text(
getStatusText(
booking["status"],
),
),
),
],
),
),
),

  const SizedBox(height: 30),

  SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: () {
        Navigator.pop(context);
      },
      icon: const Icon(Icons.arrow_back),
      label: const Text("العودة"),
    ),
  ),

],
),
),
);
}
}
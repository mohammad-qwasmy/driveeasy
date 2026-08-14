import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A small label that renders "text (count)" driven by a live Firestore
/// query — used on tab labels and screen titles across the admin/teacher
/// screens so counts are always current.
class CountLabel extends StatelessWidget {
  final String text;
  final Stream<QuerySnapshot> stream;
  final TextStyle? style;

  const CountLabel({super.key, required this.text, required this.stream, this.style});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Text("$text ($count)", style: style);
      },
    );
  }
}

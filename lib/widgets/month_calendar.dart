import 'package:flutter/material.dart';

import '../services/app_helpers.dart';

/// A simple, dependency-free month calendar grid. Shows month navigation,
/// Arabic weekday headers (week starts Saturday, matching the rest of the
/// app), and day cells. Pass [markedDates] (ISO yyyy-MM-dd strings) to put a
/// small dot under days that already have data (a schedule, bookings...).
///
/// Deliberately capped to a small max width so it never dominates the
/// screen — this is meant to be a compact date picker, not a full calendar
/// app view.
class MonthCalendar extends StatefulWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDaySelected;
  final Set<String> markedDates;
  final bool disablePastDates;

  const MonthCalendar({
    super.key,
    required this.onDaySelected,
    this.selectedDate,
    this.markedDates = const {},
    this.disablePastDates = false,
  });

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime visibleMonth;

  static const List<String> _weekdayHeaders = ["س", "ح", "ن", "ث", "ر", "خ", "ج"];
  static const List<String> _arabicMonths = [
    "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
    "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
  ];

  @override
  void initState() {
    super.initState();
    final base = widget.selectedDate ?? DateTime.now();
    visibleMonth = DateTime(base.year, base.month, 1);
  }

  void _changeMonth(int delta) {
    setState(() {
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;

    // Saturday-first weekday index (matches arabicWeekOrder elsewhere).
    final leadingBlanks = (firstOfMonth.weekday + 1) % 7;

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    final cells = <Widget>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(visibleMonth.year, visibleMonth.month, day);
      final iso = isoDate(date);
      final isPast = widget.disablePastDates && date.isBefore(todayOnly);
      final isToday = date.isAtSameMomentAs(todayOnly);
      final isSelected = widget.selectedDate != null &&
          isoDate(widget.selectedDate!) == iso;
      final hasMark = widget.markedDates.contains(iso);

      cells.add(
        GestureDetector(
          onTap: isPast ? null : () => widget.onDaySelected(date),
          child: Container(
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xff1565C0)
                  : isToday
                      ? const Color(0xffE3F2FD)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "$day",
                  style: TextStyle(
                    color: isPast
                        ? Colors.grey.shade400
                        : isSelected
                            ? Colors.white
                            : Colors.black87,
                    fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 10.5,
                  ),
                ),
                if (hasMark)
                  Container(
                    margin: const EdgeInsets.only(top: 1),
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : const Color(0xff1565C0),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeMonth(-1),
                ),
                Text(
                  "${_arabicMonths[visibleMonth.month - 1]} ${visibleMonth.year}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
            Row(
              children: _weekdayHeaders
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 1),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.4,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
              children: cells,
            ),
          ],
        ),
      ),
    );
  }
}

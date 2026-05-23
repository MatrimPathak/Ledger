import 'package:intl/intl.dart';

class DateFormatter {
  static String formatDate(DateTime date) =>
      DateFormat('d MMM yyyy').format(date);

  static String formatDateTime(DateTime date) =>
      DateFormat('d MMM yyyy, hh:mm a').format(date);

  static String formatTime(DateTime date) =>
      DateFormat('hh:mm a').format(date);

  static String formatMonth(DateTime date) =>
      DateFormat('MMMM yyyy').format(date);

  static String formatShortMonth(DateTime date) =>
      DateFormat('MMM yyyy').format(date);

  static String formatGroupHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('EEEE, d MMM').format(date);
  }

  static String formatRelative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.isNegative) return 'Just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatDate(date);
  }
}

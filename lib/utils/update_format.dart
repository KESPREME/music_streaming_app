// lib/utils/update_format.dart
//
// Words and numbers for the Software Update screen: sizes, speeds, time left,
// "checked 3 minutes ago". Pure, so every edge (zero, huge, negative, unknown)
// is a test rather than a surprise on screen.

/// "59.9 MB", "812 KB", "1.2 GB". Unknown or non-positive -> "".
String formatBytes(int bytes) {
  if (bytes <= 0) return '';
  const k = 1000.0; // what a download manager and the Play Store show
  if (bytes < k) return '$bytes B';
  if (bytes < k * k) return '${(bytes / k).round()} KB';
  if (bytes < k * k * k) {
    final mb = bytes / (k * k);
    return '${mb >= 100 ? mb.round() : mb.toStringAsFixed(1)} MB';
  }
  return '${(bytes / (k * k * k)).toStringAsFixed(1)} GB';
}

/// "4.2 MB/s", "380 KB/s". Unknown -> "".
String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond.isNaN || bytesPerSecond < 1) return '';
  final s = formatBytes(bytesPerSecond.round());
  return s.isEmpty ? '' : '$s/s';
}

/// "about 12 seconds left", "about 3 minutes left". Unknown -> "".
String formatEta(int? seconds) {
  if (seconds == null || seconds < 0) return '';
  if (seconds < 5) return 'almost done';
  if (seconds < 60) return 'about ${(seconds / 5).round() * 5} seconds left';
  final m = (seconds / 60).round();
  if (m < 60) return 'about $m minute${m == 1 ? '' : 's'} left';
  final h = (m / 60).round();
  return 'about $h hour${h == 1 ? '' : 's'} left';
}

/// "just now", "3 minutes ago", "yesterday", "12 Oct".
String formatAgo(DateTime? then, DateTime now) {
  if (then == null) return 'never';
  final d = now.difference(then);
  if (d.isNegative || d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) {
    final m = d.inMinutes < 1 ? 1 : d.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  if (d.inHours < 24) {
    return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  }
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${then.day} ${months[then.month - 1]}';
}

/// "20 Oct 2026".
String formatDate(DateTime? d) {
  if (d == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final l = d.toLocal();
  return '${l.day} ${months[l.month - 1]} ${l.year}';
}

/// "1.1.0 (142)".
String versionLabel(String name, int build) =>
    build > 0 ? '$name ($build)' : name;

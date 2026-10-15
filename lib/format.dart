/// Small, dependency-free formatting helpers.
library;

String formatTime(int minutes) {
  final m = minutes.clamp(0, 1440).toInt();
  if (m == 1440) return '12:00 AM';
  var h = m ~/ 60;
  final mm = m % 60;
  final ap = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h == 0) h = 12;
  return '$h:${mm.toString().padLeft(2, '0')} $ap';
}

String formatRange(int start, int end) => '${formatTime(start)} – ${formatTime(end)}';

String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '$h h $m min';
  if (h > 0) return '$h h';
  return '$m min';
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _weekdayLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayLetter = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Thursday, 15 Oct"
String formatHeaderDate(DateTime d) => '${_weekdayLong[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

String weekdayName(int weekday) => _weekdayLong[weekday - 1];

/// "Mon–Fri", "Sat & Sun", "Every day" or a short list.
String formatWeekdays(List<int> days) {
  final s = days.toSet();
  if (s.length == 7) return 'Every day';
  if (s.length == 5 && s.containsAll([1, 2, 3, 4, 5])) return 'Mon–Fri';
  if (s.length == 2 && s.containsAll([6, 7])) return 'Sat & Sun';
  if (s.isEmpty) return 'No days';
  final sorted = s.toList()..sort();
  return sorted.map((d) => weekdayShort[d - 1]).join(', ');
}

int minutesOfDay(DateTime d) => d.hour * 60 + d.minute;

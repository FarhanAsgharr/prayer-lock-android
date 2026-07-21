/// Streak calculation.
///
/// A "perfect day" is one where every prayer whose window closed was
/// fulfilled — completed, late, or excused. Two decisions shape this and both
/// are deliberate:
///
/// A late prayer keeps the streak. Praying Asr an hour after the window
/// closed is worse than praying it on time, but it is not the same as not
/// praying at all, and breaking someone's forty-day streak over it would
/// teach them the app is not worth using.
///
/// An excused prayer keeps the streak. Menstruation, illness and travel are
/// exemptions in fiqh, not failures. An app that punished a woman's streak
/// every month would be both wrong and offensive.
library;

import '../entities/prayer_statistics.dart';

abstract final class StreakCalculator {
  /// Compute current and longest streaks from daily summaries.
  ///
  /// [days] may be in any order and need not be contiguous; gaps are treated
  /// as breaks. [today] anchors the "current" streak.
  static StreakSummary calculate({
    required List<DailySummary> days,
    required DateTime today,
  }) {
    if (days.isEmpty) return const StreakSummary.empty();

    final perfectDays = days
        .where((day) => day.isPerfect)
        .map((day) => _dateOnly(day.date))
        .toSet();

    if (perfectDays.isEmpty) return const StreakSummary.empty();

    final sorted = perfectDays.toList()..sort();

    final longest = _longestRun(sorted);
    final current = _currentRun(perfectDays, _dateOnly(today));

    return StreakSummary(
      current: current,
      longest: longest < current ? current : longest,
      lastPerfectDay: sorted.last,
    );
  }

  /// Longest run of consecutive days in a sorted, de-duplicated list.
  static int _longestRun(List<DateTime> sorted) {
    var longest = 1;
    var run = 1;

    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].difference(sorted[i - 1]).inDays;
      if (gap == 1) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }

    return longest;
  }

  /// Length of the run ending today or yesterday.
  ///
  /// Yesterday counts because today's prayers are not all done yet. Requiring
  /// today to be complete would show every user a zero streak each morning,
  /// which is both wrong and demoralising at exactly the wrong moment.
  static int _currentRun(Set<DateTime> perfectDays, DateTime today) {
    final yesterday = today.subtract(const Duration(days: 1));

    final DateTime anchor;
    if (perfectDays.contains(today)) {
      anchor = today;
    } else if (perfectDays.contains(yesterday)) {
      anchor = yesterday;
    } else {
      return 0;
    }

    var count = 0;
    var cursor = anchor;
    while (perfectDays.contains(cursor)) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return count;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

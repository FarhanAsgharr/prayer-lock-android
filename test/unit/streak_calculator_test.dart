/// Tests for streaks and statistics.
///
/// Streaks are the app's main motivational mechanic, which makes a wrong
/// answer expensive: telling someone their forty-day streak is broken when it
/// is not is the kind of bug that gets an app uninstalled.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/tracking/domain/entities/prayer_statistics.dart';
import 'package:prayer_lock/features/tracking/domain/usecases/streak_calculator.dart';

final today = DateTime(2026, 7, 20);

DailySummary day(int daysAgo, PrayerCounts counts) => DailySummary(
      date: today.subtract(Duration(days: daysAgo)),
      counts: counts,
    );

const perfect = PrayerCounts(completed: 5);
const perfectWithLate = PrayerCounts(completed: 4, late: 1);
const perfectWithExcused = PrayerCounts(completed: 4, excused: 1);
const brokenDay = PrayerCounts(completed: 4, missed: 1);

void main() {
  group('counts', () {
    test('success rate ignores excused prayers', () {
      // Counting an excused prayer as a success would inflate the rate and
      // make the number meaningless.
      const counts = PrayerCounts(completed: 3, missed: 1, excused: 1);

      expect(counts.assessed, 4);
      expect(counts.successRate, 0.75);
    });

    test('late prayers count towards success but not on-time', () {
      const counts = PrayerCounts(completed: 3, late: 2);

      expect(counts.successRate, 1.0);
      expect(counts.onTimeRate, 0.6);
    });

    test('a fresh install shows 100%, not 0%', () {
      // Showing 0% to someone who has not had the chance to pray yet reads as
      // an accusation on first launch.
      const counts = PrayerCounts();

      expect(counts.successRate, 1.0);
      expect(counts.assessed, 0);
    });

    test('pending and active prayers are not assessed', () {
      final counts = PrayerCounts.fromStatuses([
        PrayerStatus.completed,
        PrayerStatus.pending,
        PrayerStatus.active,
      ]);

      expect(counts.completed, 1);
      expect(counts.assessed, 1);
    });

    test('counts add together', () {
      const a = PrayerCounts(completed: 2, missed: 1);
      const b = PrayerCounts(completed: 3, late: 1);
      final total = a + b;

      expect(total.completed, 5);
      expect(total.missed, 1);
      expect(total.late, 1);
    });
  });

  group('perfect days', () {
    test('all completed is perfect', () {
      expect(day(0, perfect).isPerfect, isTrue);
    });

    test('a late prayer still makes a perfect day', () {
      // Late is worse than on time, but it is not the same as not praying,
      // and breaking a long streak over it would teach the user to give up.
      expect(day(0, perfectWithLate).isPerfect, isTrue);
    });

    test('an excused prayer still makes a perfect day', () {
      // Menstruation, illness and travel are exemptions in fiqh, not failures.
      expect(day(0, perfectWithExcused).isPerfect, isTrue);
    });

    test('a missed prayer breaks the day', () {
      expect(day(0, brokenDay).isPerfect, isFalse);
    });

    test('a day with nothing assessed is not perfect', () {
      // An untouched future day must not silently count towards a streak.
      expect(day(0, const PrayerCounts()).isPerfect, isFalse);
    });
  });

  group('current streak', () {
    test('counts consecutive perfect days ending today', () {
      final summary = StreakCalculator.calculate(
        days: [day(0, perfect), day(1, perfect), day(2, perfect)],
        today: today,
      );

      expect(summary.current, 3);
    });

    test('counts a streak ending yesterday', () {
      // Today's prayers are not all done yet. Requiring today to be complete
      // would show every user a zero streak each morning.
      final summary = StreakCalculator.calculate(
        days: [day(1, perfect), day(2, perfect)],
        today: today,
      );

      expect(summary.current, 2);
    });

    test('is zero when the last perfect day was two days ago', () {
      final summary = StreakCalculator.calculate(
        days: [day(2, perfect), day(3, perfect)],
        today: today,
      );

      expect(summary.current, 0);
    });

    test('stops at a broken day', () {
      final summary = StreakCalculator.calculate(
        days: [
          day(0, perfect),
          day(1, perfect),
          day(2, brokenDay),
          day(3, perfect),
        ],
        today: today,
      );

      expect(summary.current, 2);
    });

    test('stops at a gap in recorded days', () {
      // A missing day is a break, not a bridge: the user simply did not use
      // the app, and inventing a perfect day would be dishonest.
      final summary = StreakCalculator.calculate(
        days: [day(0, perfect), day(1, perfect), day(3, perfect)],
        today: today,
      );

      expect(summary.current, 2);
    });

    test('is zero with no perfect days at all', () {
      final summary = StreakCalculator.calculate(
        days: [day(0, brokenDay), day(1, brokenDay)],
        today: today,
      );

      expect(summary.current, 0);
      expect(summary.longest, 0);
    });

    test('is zero with no data', () {
      final summary = StreakCalculator.calculate(days: [], today: today);

      expect(summary.current, 0);
      expect(summary.longest, 0);
      expect(summary.lastPerfectDay, isNull);
    });
  });

  group('longest streak', () {
    test('finds the best historical run', () {
      final summary = StreakCalculator.calculate(
        days: [
          day(0, perfect),
          day(1, brokenDay),
          day(2, perfect),
          day(3, perfect),
          day(4, perfect),
          day(5, perfect),
          day(6, brokenDay),
        ],
        today: today,
      );

      expect(summary.longest, 4);
      expect(summary.current, 1);
    });

    test('is never less than the current streak', () {
      final summary = StreakCalculator.calculate(
        days: List.generate(10, (i) => day(i, perfect)),
        today: today,
      );

      expect(summary.longest, greaterThanOrEqualTo(summary.current));
      expect(summary.current, 10);
    });

    test('handles a single perfect day', () {
      final summary = StreakCalculator.calculate(
        days: [day(0, perfect)],
        today: today,
      );

      expect(summary.current, 1);
      expect(summary.longest, 1);
    });

    test('records the last perfect day', () {
      final summary = StreakCalculator.calculate(
        days: [day(3, perfect), day(1, perfect)],
        today: today,
      );

      expect(summary.lastPerfectDay, today.subtract(const Duration(days: 1)));
    });

    test('tolerates unsorted input', () {
      final summary = StreakCalculator.calculate(
        days: [day(2, perfect), day(0, perfect), day(1, perfect)],
        today: today,
      );

      expect(summary.current, 3);
    });

    test('a long unbroken history counts correctly', () {
      final summary = StreakCalculator.calculate(
        days: List.generate(365, (i) => day(i, perfect)),
        today: today,
      );

      expect(summary.current, 365);
      expect(summary.longest, 365);
    });
  });

  group('weakest prayer', () {
    test('identifies the prayer with the lowest success rate', () {
      const statistics = PrayerStatistics(
        today: PrayerCounts(),
        week: PrayerCounts(),
        month: PrayerCounts(),
        year: PrayerCounts(),
        allTime: PrayerCounts(),
        streak: StreakSummary.empty(),
        dailyHistory: [],
        byPrayer: {
          PrayerName.fajr: PrayerCounts(completed: 3, missed: 7),
          PrayerName.dhuhr: PrayerCounts(completed: 9, missed: 1),
          PrayerName.asr: PrayerCounts(completed: 10),
        },
      );

      expect(statistics.weakestPrayer, PrayerName.fajr);
    });

    test('ignores prayers with too little data', () {
      // One missed prayer in a new install must not be labelled a weakness.
      const statistics = PrayerStatistics(
        today: PrayerCounts(),
        week: PrayerCounts(),
        month: PrayerCounts(),
        year: PrayerCounts(),
        allTime: PrayerCounts(),
        streak: StreakSummary.empty(),
        dailyHistory: [],
        byPrayer: {
          PrayerName.fajr: PrayerCounts(missed: 1),
          PrayerName.dhuhr: PrayerCounts(completed: 9, missed: 1),
        },
      );

      expect(statistics.weakestPrayer, PrayerName.dhuhr);
    });

    test('is null without enough data anywhere', () {
      const statistics = PrayerStatistics.empty();
      expect(statistics.weakestPrayer, isNull);
    });
  });
}

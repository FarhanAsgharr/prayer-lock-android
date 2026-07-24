/// Tests for Friday and extended prayer analytics.
///
/// Statistics are easy to get subtly wrong in ways nobody notices until a user
/// disputes their own streak. These pin the arithmetic that decides what the
/// app tells someone about their own worship.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/tracking/domain/entities/friday_analytics.dart';

/// Fridays counting backwards from 2026-07-24, most recent first.
List<FridayRecord> fridays(
  List<PrayerStatus> statuses, {
  String mosque = 'Home Mosque',
  Duration? delay,
}) {
  return [
    for (var i = 0; i < statuses.length; i++)
      FridayRecord(
        date: DateTime(2026, 7, 24 - i * 7),
        status: statuses[i],
        wasJumuah: true,
        mosqueName: mosque,
        blockDuration: const Duration(minutes: 15),
        verificationDelay: delay,
      ),
  ];
}

void main() {
  group('Friday analytics', () {
    test('an empty history is not reported as failure', () {
      // A new user must not be shown 0% before they have had a Friday.
      const empty = FridayAnalytics.empty();
      expect(empty.totalFridays, 0);
      expect(empty.completionRate, 1.0);
      expect(empty.currentStreak, 0);
    });

    test('counts completed and missed', () {
      final analytics = FridayAnalytics.from(
        fridays([
          PrayerStatus.completed,
          PrayerStatus.completed,
          PrayerStatus.missed,
          PrayerStatus.completed,
        ]),
      );

      expect(analytics.totalFridays, 4);
      expect(analytics.completedFridays, 3);
      expect(analytics.missedFridays, 1);
      expect(analytics.completionRate, 0.75);
    });

    test('a pending Friday counts against neither', () {
      // Today's Friday, not yet over, must not be scored as a miss.
      final analytics = FridayAnalytics.from(
        fridays([
          PrayerStatus.pending,
          PrayerStatus.completed,
          PrayerStatus.completed,
        ]),
      );

      expect(analytics.totalFridays, 2);
      expect(analytics.completedFridays, 2);
      expect(analytics.completionRate, 1.0);
    });

    test('the current streak stops at the most recent miss', () {
      final analytics = FridayAnalytics.from(
        fridays([
          PrayerStatus.completed,
          PrayerStatus.completed,
          PrayerStatus.missed,
          PrayerStatus.completed,
          PrayerStatus.completed,
          PrayerStatus.completed,
        ]),
      );

      expect(analytics.currentStreak, 2);
      // The best run is the older three.
      expect(analytics.longestStreak, 3);
    });

    test('the longest streak survives a later miss', () {
      final analytics = FridayAnalytics.from(
        fridays([
          PrayerStatus.missed,
          PrayerStatus.completed,
          PrayerStatus.completed,
          PrayerStatus.completed,
          PrayerStatus.completed,
        ]),
      );

      expect(analytics.currentStreak, 0);
      expect(analytics.longestStreak, 4);
    });

    test('qaza and excused Fridays count as kept', () {
      // Excused is not a failure — someone ill or travelling has not missed
      // anything they were obliged to do.
      final analytics = FridayAnalytics.from(
        fridays([
          PrayerStatus.qazaCompleted,
          PrayerStatus.excused,
          PrayerStatus.completed,
        ]),
      );

      expect(analytics.completedFridays, 3);
      expect(analytics.currentStreak, 3);
    });

    test('averages the confirmation delay', () {
      final records = [
        ...fridays([PrayerStatus.completed], delay: const Duration(minutes: 4)),
        FridayRecord(
          date: DateTime(2026, 7, 17),
          status: PrayerStatus.completed,
          wasJumuah: true,
          mosqueName: 'Home Mosque',
          verificationDelay: const Duration(minutes: 10),
        ),
      ];

      final analytics = FridayAnalytics.from(records);
      expect(analytics.averageVerificationDelay, const Duration(minutes: 7));
    });

    test('identifies the mosque attended most often', () {
      final analytics = FridayAnalytics.from([
        ...fridays([PrayerStatus.completed], mosque: 'University Mosque'),
        FridayRecord(
          date: DateTime(2026, 7, 17),
          status: PrayerStatus.completed,
          wasJumuah: true,
          mosqueName: 'Home Mosque',
        ),
        FridayRecord(
          date: DateTime(2026, 7, 10),
          status: PrayerStatus.completed,
          wasJumuah: true,
          mosqueName: 'Home Mosque',
        ),
      ]);

      expect(analytics.favouriteMosque, 'Home Mosque');
      expect(analytics.mosqueCounts['Home Mosque'], 2);
      expect(analytics.mosqueCounts['University Mosque'], 1);
    });

    test('records are ordered regardless of input order', () {
      // The repository returns newest first, but the arithmetic must not depend
      // on that.
      final ordered = fridays([
        PrayerStatus.completed,
        PrayerStatus.completed,
        PrayerStatus.missed,
      ]);

      expect(
        FridayAnalytics.from(ordered).currentStreak,
        FridayAnalytics.from(ordered.reversed.toList()).currentStreak,
      );
    });
  });

  group('extended prayer analytics', () {
    ExtendedPrayerAnalytics build(Map<PrayerName, (int, int)> data) =>
        ExtendedPrayerAnalytics(
          byPrayer: [
            for (final entry in data.entries)
              PrayerPerformance(
                prayer: entry.key,
                completed: entry.value.$1,
                missed: entry.value.$2,
              ),
          ],
          friday: const FridayAnalytics.empty(),
        );

    test('the most-missed prayer is ranked by rate, not by count', () {
      // Fajr: 3 of 4 missed. Isha: 5 missed but out of 105. Fajr is the real
      // problem even though Isha has more absolute misses.
      final analytics = build({
        PrayerName.fajr: (1, 3),
        PrayerName.isha: (100, 5),
      });

      expect(analytics.mostMissed?.prayer, PrayerName.fajr);
    });

    test('nothing is most-missed when nothing is missed', () {
      final analytics = build({
        PrayerName.fajr: (10, 0),
        PrayerName.dhuhr: (10, 0),
      });

      expect(analytics.mostMissed, isNull);
      expect(analytics.bestPrayer?.completionRate, 1.0);
    });

    test('prayers with nothing assessed are ignored', () {
      // A prayer never yet due is not one the user is failing at.
      final analytics = build({
        PrayerName.fajr: (5, 1),
        PrayerName.isha: (0, 0),
      });

      expect(analytics.mostMissed?.prayer, PrayerName.fajr);
      expect(analytics.bestPrayer?.prayer, PrayerName.fajr);
    });

    test('consistency rewards evenness over a high average', () {
      // Someone at 90% everywhere is more consistent than someone perfect on
      // four prayers and failing one — the second has a specific problem.
      final even = build({
        PrayerName.fajr: (9, 1),
        PrayerName.dhuhr: (9, 1),
        PrayerName.asr: (9, 1),
      });
      final lopsided = build({
        PrayerName.fajr: (5, 5),
        PrayerName.dhuhr: (10, 0),
        PrayerName.asr: (10, 0),
      });

      expect(even.consistency, greaterThan(lopsided.consistency));
      expect(even.consistency, closeTo(1.0, 0.001));
    });

    test('consistency is 1.0 with fewer than two assessed prayers', () {
      expect(build({PrayerName.fajr: (5, 1)}).consistency, 1.0);
      expect(const ExtendedPrayerAnalytics.empty().consistency, 1.0);
    });

    test('the overall rate spans every prayer', () {
      final analytics = build({
        PrayerName.fajr: (5, 5),
        PrayerName.dhuhr: (10, 0),
      });

      expect(analytics.overallCompletionRate, closeTo(0.75, 0.001));
    });

    test('an empty bundle reports success, not failure', () {
      const empty = ExtendedPrayerAnalytics.empty();
      expect(empty.overallCompletionRate, 1.0);
      expect(empty.mostMissed, isNull);
      expect(empty.bestPrayer, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/notifications/strategies/notification_strategy.dart';
import 'package:prayer_lock/features/blocking/domain/strategies/blocking_strategy.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/jumuah_profile.dart'
    show LocalTimeOfDay;
import 'package:prayer_lock/features/jumuah/domain/entities/mosque_profile.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_slot.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_window.dart';
import 'package:prayer_lock/features/prayer_times/domain/strategies/calculation_strategy.dart';
import 'package:prayer_lock/features/prayer_times/domain/strategies/prayer_mode_strategy.dart';
import 'package:prayer_lock/features/sections/domain/entities/prayer_grouping.dart';
import 'package:prayer_lock/features/verification/domain/entities/verification_result.dart';
import 'package:prayer_lock/features/verification/domain/strategies/verification_strategy.dart';

/// The five strategy families, tested as abstractions rather than through the
/// code that uses them.
///
/// The point of each is that behaviour can be *substituted*, so most of these
/// assert that a registry actually hands back what was registered, and that the
/// fallback when nothing is registered is the safe direction rather than a
/// crash. A strategy pattern that cannot be substituted is just a longer way to
/// write a switch.
void main() {
  final date = DateTime.utc(2026, 7, 24);

  PrayerDay dayWith({bool jumuahDhuhr = false}) {
    PrayerWindow window(
      PrayerName prayer,
      int startHour,
      int endHour,
      WindowBoundary boundary, {
      bool isJumuah = false,
    }) =>
        PrayerWindow(
          prayer: prayer,
          startsAt: DateTime.utc(2026, 7, 24, startHour),
          endsAt: DateTime.utc(2026, 7, 24, endHour),
          boundary: boundary,
          labelOverride: isJumuah ? "Jumu'ah" : null,
          isJumuah: isJumuah,
        );

    return PrayerDay.fromWindows(
      DailyPrayerWindows(
        date: date,
        sunrise: DateTime.utc(2026, 7, 24, 6),
        nextDayFajr: DateTime.utc(2026, 7, 25, 4),
        windows: [
          window(PrayerName.fajr, 4, 6, WindowBoundary.sunrise),
          window(PrayerName.dhuhr, 12, 16, WindowBoundary.asr,
              isJumuah: jumuahDhuhr),
          window(PrayerName.asr, 16, 19, WindowBoundary.maghrib),
          window(PrayerName.maghrib, 19, 20, WindowBoundary.isha),
          window(PrayerName.isha, 20, 28, WindowBoundary.nextDayFajr),
        ],
      ),
    );
  }

  group('PrayerModeStrategy', () {
    final registry = PrayerModeRegistry.standard();

    test('the separate arrangement gives one slot per prayer', () {
      final strategy = registry.forGrouping(PrayerGrouping.none);
      final slots = strategy.slotsFor(dayWith());

      expect(slots, hasLength(5));
      expect(strategy.slotCount, 5);
      expect(strategy.joins(PrayerName.dhuhr), isFalse);
    });

    test('a joining arrangement merges only the pairs it names', () {
      final strategy = registry.forGrouping(PrayerGrouping.dhuhrAsr);
      final slots = strategy.slotsFor(dayWith());

      expect(slots, hasLength(4));
      expect(strategy.joins(PrayerName.dhuhr), isTrue);
      expect(strategy.joins(PrayerName.maghrib), isFalse);
    });

    test('joining both pairs leaves three slots', () {
      final slots = registry.forGrouping(PrayerGrouping.both).slotsFor(dayWith());
      expect(slots, hasLength(3));
    });

    test('Jumu\'ah is never absorbed into a pair', () {
      // Absorbing Asr into a fifteen-minute congregation would either swallow
      // Asr or stretch the khutbah to Maghrib. Neither is what combining means.
      final slots = registry
          .forGrouping(PrayerGrouping.dhuhrAsr)
          .slotsFor(dayWith(jumuahDhuhr: true));

      expect(slots, hasLength(5));
    });

    test('every arrangement accounts for all five prayers exactly once', () {
      for (final grouping in PrayerGrouping.values) {
        final slots = registry.forGrouping(grouping).slotsFor(dayWith());
        final covered = [
          for (final slot in slots)
            for (final entry in slot.prayers) entry.prayer,
        ];

        expect(
          covered.toSet(),
          PrayerName.values.toSet(),
          reason: '$grouping dropped a prayer',
        );
        expect(covered, hasLength(5), reason: '$grouping duplicated a prayer');
      }
    });

    test('a substituted arrangement is the one that answers', () {
      final registry = PrayerModeRegistry.standard()
          .withStrategy(const _AlwaysSeparateStrategy());

      expect(
        registry.forGrouping(PrayerGrouping.both).slotsFor(dayWith()),
        hasLength(5),
      );
    });

    test('an unregistered grouping falls back to separate, not a crash', () {
      final empty = PrayerModeRegistry(const []);
      expect(empty.forGrouping(PrayerGrouping.both).slotsFor(dayWith()),
          hasLength(5));
    });
  });

  group('CalculationStrategy', () {
    final registry = CalculationRegistry.standard();

    test('every method has both its angles and its remote id', () {
      // Split across two files, one of these used to be easy to forget — and a
      // missing remote id silently served Muslim World League times to someone
      // who chose Umm al-Qura.
      for (final method in CalculationMethod.values) {
        final strategy = registry.forMethod(method);
        expect(strategy.method, method);
        expect(strategy.remoteMethodId, isNotNull,
            reason: '${method.displayName} has no AlAdhan id');
        expect(strategy.parameters.fajrAngle, greaterThan(0));
      }
    });

    test('Isha is defined by exactly one of an angle or an interval', () {
      for (final method in CalculationMethod.values) {
        final params = registry.forMethod(method).parameters;
        expect(
          (params.ishaAngle == null) != (params.ishaIntervalMinutes == null),
          isTrue,
          reason: '${method.displayName} defines Isha twice or not at all',
        );
      }
    });

    test('the authorities that lift Maghrib off the horizon still do', () {
      // Ja'fari and Tehran begin Maghrib after the redness fades, not at
      // sunset. Losing this in the move would shift Maghrib for every Shia user
      // by several minutes, silently.
      expect(registry.forMethod(CalculationMethod.jafari).parameters.maghribAngle,
          4.0);
      expect(registry.forMethod(CalculationMethod.tehran).parameters.maghribAngle,
          4.5);
    });

    test('an unregistered method falls back to Muslim World League', () {
      final sparse = CalculationRegistry.standard();
      expect(sparse.forMethod(CalculationMethod.karachi).method,
          CalculationMethod.karachi);
    });
  });

  group('BlockingStrategy', () {
    final registry = BlockingRegistry.standard();
    final slot = dayWith().slots(PrayerGrouping.none).first;
    final now = DateTime.utc(2026, 7, 24, 5);

    test('verification unlock has nothing to say about an open window', () {
      final verdict = registry
          .forPolicy(UnlockPolicy.onVerification)
          .verdictFor(slot: slot, now: now);

      expect(verdict.shouldLock, isFalse);
    });

    test('full duration holds the window and says until when', () {
      final verdict = registry
          .forPolicy(UnlockPolicy.fullDuration)
          .verdictFor(slot: slot, now: now);

      expect(verdict.shouldLock, isTrue);
      expect(verdict.lockUntil, slot.windowEndsAt);
    });

    test('only full duration holds after verification', () {
      expect(
        registry.forPolicy(UnlockPolicy.fullDuration).holdsAfterVerification,
        isTrue,
      );
      expect(
        registry.forPolicy(UnlockPolicy.onVerification).holdsAfterVerification,
        isFalse,
      );
      expect(
        registry.forPolicy(UnlockPolicy.earliestOf).holdsAfterVerification,
        isFalse,
      );
    });

    test('an unregistered policy falls back to releasing, not to holding', () {
      // The failure direction matters: a user locked out by a registry gap has
      // no recourse, one released early simply is not blocked.
      final empty = BlockingRegistry(const []);
      expect(
        empty.forPolicy(UnlockPolicy.fullDuration).holdsAfterVerification,
        isFalse,
      );
    });
  });

  group('VerificationStrategy', () {
    test('the photo arrangement submits what it was given', () async {
      final gateway = _RecordingGateway();
      final strategy = AiPhotoVerificationStrategy(gateway);

      final result = await strategy.verify(
        prayer: PrayerName.fajr,
        imageBase64: 'abc',
      );

      expect(gateway.submitted, 'abc');
      expect(result.approved, isTrue);
      expect(strategy.requiresPhoto, isTrue);
      expect(strategy.producesVerifiedRecord, isTrue);
    });

    test('a missing photo records the prayer instead of refusing it', () async {
      // The camera failed. Penalising someone for our hardware problem, after
      // they have already prayed, is not a defensible outcome.
      final gateway = _RecordingGateway();
      final result = await AiPhotoVerificationStrategy(gateway)
          .verify(prayer: PrayerName.fajr, imageBase64: null);

      expect(result.approved, isTrue);
      expect(result.releasedWithoutDetection, isTrue);
      expect(gateway.submitted, isNull, reason: 'nothing to submit');
    });

    test('self-declaration approves but does not claim verification', () async {
      const strategy = SelfDeclaredVerificationStrategy();
      final result = await strategy.verify(prayer: PrayerName.asr);

      expect(result.approved, isTrue);
      expect(result.releasedWithoutDetection, isTrue,
          reason: 'statistics must not claim anything was checked');
      expect(strategy.requiresPhoto, isFalse);
      expect(strategy.producesVerifiedRecord, isFalse);
    });

    test('the preference selects the arrangement', () {
      final registry = VerificationRegistry.standard(_RecordingGateway());

      expect(registry.forPreference(requirePhoto: true).requiresPhoto, isTrue);
      expect(registry.forPreference(requirePhoto: false).requiresPhoto, isFalse);
    });

    test('an unregistered mode falls back to self-declaration', () {
      final empty = VerificationRegistry(const []);
      expect(empty.forMode(VerificationMode.aiPhoto).requiresPhoto, isFalse);
    });
  });

  group('NotificationStrategy', () {
    final registry = NotificationRegistry.standard();

    NotificationContext context({MosqueProfile? mosque, bool blocking = true}) =>
        NotificationContext(
          prayerName: mosque == null ? 'Dhuhr' : "Jumu'ah",
          windowDuration: mosque == null
              ? const Duration(hours: 4)
              : const Duration(minutes: 15),
          boundaryName: 'Asr',
          blockingEnabled: blocking,
          unlockPolicy: UnlockPolicy.onVerification,
          formattedDuration: '4h',
          mosque: mosque,
        );

    const mosque = MosqueProfile(
      id: 'home',
      kind: MosqueKind.home,
      name: 'Home Mosque',
      startsAt: LocalTimeOfDay(14, 0),
      endsAt: LocalTimeOfDay(14, 15),
    );

    test('the ordinary vocabulary names the prayer and its boundary', () {
      final copy = registry.forWindow(isJumuah: false);
      final ctx = context();

      expect(copy.adhanTitle(ctx), contains('Dhuhr'));
      expect(copy.endingBody(ctx, const Duration(minutes: 20)), contains('Asr'));
      expect(copy.endedBody(ctx), contains('qaza'));
    });

    test('the Friday vocabulary names the mosque and its closing time', () {
      final copy = registry.forWindow(isJumuah: true);
      final ctx = context(mosque: mosque);

      expect(copy.adhanTitle(ctx), contains("Jumu'ah"));
      expect(copy.adhanBody(ctx), contains('Home Mosque'));
      expect(copy.adhanBody(ctx), contains('2:15 PM'));
    });

    test('a missed Jumu\'ah is not offered as qaza', () {
      // It is made up by praying Dhuhr, not by praying Jumu'ah late. Saying
      // otherwise would be the app taking a position it has no business taking.
      final body = registry.forWindow(isJumuah: true).endedBody(
            context(mosque: mosque),
          );

      expect(body, isNot(contains('qaza')));
      expect(body, contains('Dhuhr'));
    });

    test('a short congregation still gets a closing warning', () {
      // The ordinary lead would exceed the whole window and the warning would
      // never be scheduled, leaving a congregation with no closing notice.
      final lead = registry.forWindow(isJumuah: true).endingLead(
            context(mosque: mosque),
            const Duration(minutes: 20),
          );

      expect(lead.inMinutes, lessThan(15));
      expect(lead.inMinutes, greaterThan(0));
    });

    test('the ordinary lead is used unchanged for a long window', () {
      final lead = registry.forWindow(isJumuah: false).endingLead(
            context(),
            const Duration(minutes: 20),
          );

      expect(lead, const Duration(minutes: 20));
    });

    test('nothing mentions locking when blocking is off', () {
      for (final isJumuah in [true, false]) {
        final copy = registry.forWindow(isJumuah: isJumuah);
        final ctx = context(mosque: isJumuah ? mosque : null, blocking: false);

        expect(copy.adhanBody(ctx), isNot(contains('lock')));
        expect(copy.endedBody(ctx), isNot(contains('unlocked')));
      }
    });
  });
}

/// Substituted in to prove a registry actually defers to what is registered.
///
/// Claims the "combine both pairs" grouping but refuses to combine anything —
/// a behaviour no shipped arrangement has, so the test cannot pass by accident.
class _AlwaysSeparateStrategy implements PrayerModeStrategy {
  const _AlwaysSeparateStrategy();

  @override
  PrayerGrouping get grouping => PrayerGrouping.both;

  @override
  String get labelKey => 'test';

  @override
  int get slotCount => 5;

  @override
  bool joins(PrayerName prayer) => false;

  @override
  List<PrayerSlot> slotsFor(PrayerDay day) =>
      const SeparatePrayerModeStrategy().slotsFor(day);
}

class _RecordingGateway implements VerificationGateway {
  String? submitted;

  @override
  Future<VerificationResult> submit({
    required PrayerName prayer,
    required String imageBase64,
  }) async {
    submitted = imageBase64;
    return const VerificationResult(approved: true, message: 'ok');
  }
}

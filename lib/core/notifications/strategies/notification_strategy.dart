/// What each prayer notice says.
///
/// Every notice this app sends comes in two versions — the ordinary one and the
/// Friday one — and before this existed the choice between them was five
/// `jumuah != null ? … : …` ternaries stacked inside one 120-line function.
/// Each was correct. Together they meant that adding a third kind of window,
/// say Taraweeh during Ramadan, would have turned every ternary into a
/// three-way conditional in a function already hard to read.
///
/// A strategy supplies one window's whole vocabulary. The scheduler asks the
/// registry which one applies and then never branches again — it decides *when*
/// notices fire, and the strategy decides what they say. Those are genuinely
/// separate concerns: the timing rules are safety-critical and the wording is
/// not, and mixing them meant a copy change touched scheduling code.
library;

import '../../../features/jumuah/domain/entities/mosque_profile.dart';
import '../../../features/prayer_times/domain/entities/prayer_enums.dart';

/// Everything a notice's wording can depend on.
///
/// Passed as one object rather than eight parameters so adding something a
/// future strategy needs does not change every method signature in the
/// interface and every implementation of it.
class NotificationContext {
  const NotificationContext({
    required this.prayerName,
    required this.windowDuration,
    required this.boundaryName,
    required this.blockingEnabled,
    required this.unlockPolicy,
    required this.formattedDuration,
    this.mosque,
  });

  /// What to call the prayer — already resolved, so "Jumu'ah" not "Dhuhr".
  final String prayerName;

  final Duration windowDuration;

  /// What ends the window: "Sunrise", "Asr", "Midnight".
  final String boundaryName;

  final bool blockingEnabled;
  final UnlockPolicy unlockPolicy;

  /// The window length in words — "3h 24m".
  final String formattedDuration;

  /// The congregation's mosque, on a Friday with one chosen.
  final MosqueProfile? mosque;
}

/// One window's vocabulary.
abstract interface class NotificationStrategy {
  /// Identifies this strategy. Used in logs and tests, not shown to users.
  String get id;

  String adhanTitle(NotificationContext context);
  String adhanBody(NotificationContext context);

  String reminderTitle(NotificationContext context, int minutes);
  String reminderBody(NotificationContext context, int minutes);

  /// How far ahead of the window's close to warn.
  ///
  /// A strategy's own decision because it depends on how long the window is,
  /// which differs by an order of magnitude between an ordinary prayer and a
  /// congregation.
  Duration endingLead(NotificationContext context, Duration defaultLead);

  String endingTitle(NotificationContext context);
  String endingBody(NotificationContext context, Duration lead);

  String endedTitle(NotificationContext context);
  String endedBody(NotificationContext context);
}

/// The wording for an ordinary prayer.
class StandardNotificationStrategy implements NotificationStrategy {
  const StandardNotificationStrategy();

  @override
  String get id => 'standard';

  @override
  String adhanTitle(NotificationContext context) =>
      "It's time for ${context.prayerName}";

  @override
  String adhanBody(NotificationContext context) {
    if (!context.blockingEnabled) return 'May Allah accept your prayer.';

    return switch (context.unlockPolicy) {
      UnlockPolicy.fullDuration =>
        'Apps are locked for the next ${context.formattedDuration}.',
      _ => 'Apps are locked until you verify your prayer.',
    };
  }

  @override
  String reminderTitle(NotificationContext context, int minutes) =>
      '${context.prayerName} in $minutes '
      '${minutes == 1 ? 'minute' : 'minutes'}';

  @override
  String reminderBody(NotificationContext context, int minutes) =>
      // The last rung is the one that should change behaviour, so it says what
      // is about to happen rather than repeating the countdown.
      context.blockingEnabled && minutes <= 5
          ? 'Selected apps lock when ${context.prayerName} begins.'
          : 'Prepare for prayer.';

  @override
  Duration endingLead(NotificationContext context, Duration defaultLead) =>
      defaultLead;

  @override
  String endingTitle(NotificationContext context) =>
      '${context.prayerName} window ends soon';

  @override
  String endingBody(NotificationContext context, Duration lead) =>
      '${lead.inMinutes} minutes left to pray ${context.prayerName} '
      'before ${context.boundaryName}.';

  @override
  String endedTitle(NotificationContext context) =>
      '${context.prayerName} window has ended';

  @override
  String endedBody(NotificationContext context) => context.blockingEnabled
      ? 'Apps are unlocked. You can still pray ${context.prayerName} as qaza '
          'today.'
      : 'You can still pray ${context.prayerName} as qaza today.';
}

/// The wording for the Friday congregation.
///
/// Names the mosque, because that is the one detail that differs between people
/// and the one that makes the notice actionable — "Jumu'ah in 30 minutes" is a
/// fact, "Jumu'ah at University Mosque in 30 minutes" is a reason to leave.
class JumuahNotificationStrategy implements NotificationStrategy {
  const JumuahNotificationStrategy();

  @override
  String get id => 'jumuah';

  @override
  String adhanTitle(NotificationContext context) => "Jumu'ah has started";

  @override
  String adhanBody(NotificationContext context) {
    final mosque = context.mosque;
    if (mosque == null) {
      return context.blockingEnabled
          ? 'The congregation has begun. Apps are locked until you confirm.'
          : 'The congregation has begun.';
    }

    // The closing time earns its place: a congregation window is short, and
    // someone reading this on the way in wants to know how long they have.
    return context.blockingEnabled
        ? '${mosque.displayName}, until ${mosque.endsAt.format()}. '
            'Apps are locked until you confirm.'
        : '${mosque.displayName}, until ${mosque.endsAt.format()}.';
  }

  @override
  String reminderTitle(NotificationContext context, int minutes) =>
      "Jumu'ah in $minutes ${minutes == 1 ? 'minute' : 'minutes'}";

  @override
  String reminderBody(NotificationContext context, int minutes) {
    final mosque = context.mosque;
    if (mosque == null) return 'Time to leave for the congregation.';

    return context.blockingEnabled
        ? '${mosque.displayName} at ${mosque.formattedRange}. '
            'Apps lock when it begins.'
        : '${mosque.displayName} at ${mosque.formattedRange}.';
  }

  @override
  Duration endingLead(NotificationContext context, Duration defaultLead) {
    // A Jumu'ah window is short by design — often fifteen minutes — so the
    // usual lead is scaled down rather than skipped, which would leave a
    // congregation with no closing warning at all.
    final scaled = (context.windowDuration.inMinutes / 3).clamp(1, 15).round();
    return Duration(minutes: scaled);
  }

  @override
  String endingTitle(NotificationContext context) => "Jumu'ah time is ending";

  @override
  String endingBody(NotificationContext context, Duration lead) {
    final mosque = context.mosque;
    final at = mosque == null ? '' : ' at ${mosque.displayName}';
    return '${lead.inMinutes} minutes left in the congregation$at.';
  }

  @override
  String endedTitle(NotificationContext context) => "Jumu'ah has ended";

  @override
  String endedBody(NotificationContext context) => context.blockingEnabled
      // Deliberately not offered as qaza. A missed Jumu'ah is made up by
      // praying Dhuhr, not by praying Jumu'ah late, and telling a user
      // otherwise would be the app taking a position it has no business taking.
      ? 'Apps are unlocked. Pray Dhuhr if you missed the congregation.'
      : 'Pray Dhuhr if you missed the congregation.';
}

/// Chooses the vocabulary for a window.
class NotificationRegistry {
  NotificationRegistry({
    required NotificationStrategy standard,
    required NotificationStrategy jumuah,
  })  : _standard = standard,
        _jumuah = jumuah;

  /// The vocabularies the app ships with.
  factory NotificationRegistry.standard() => NotificationRegistry(
        standard: const StandardNotificationStrategy(),
        jumuah: const JumuahNotificationStrategy(),
      );

  final NotificationStrategy _standard;
  final NotificationStrategy _jumuah;

  /// The strategy for a window.
  ///
  /// Keyed on whether the window *is* a congregation, never on the weekday. By
  /// the time the scheduler asks, a Friday Dhuhr window has already been
  /// replaced by the mosque's — so asking "is it Friday" here would be asking
  /// the same question twice and getting it wrong the second time for anyone
  /// who turned Jumu'ah off.
  NotificationStrategy forWindow({required bool isJumuah}) =>
      isJumuah ? _jumuah : _standard;

  List<NotificationStrategy> get all => List.unmodifiable([_standard, _jumuah]);
}

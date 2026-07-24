/// The wording of Friday notifications.
///
/// The *scheduling* of Jumu'ah notices needs no special case at all: the
/// Jumu'ah window replaces the Dhuhr window before the planner runs, so the
/// existing reminder ladder, adhan, window-ending and window-ended notices fire
/// against the mosque's times automatically and only on days where such a
/// window exists. That is why there is no Friday check in the scheduler.
///
/// What *is* different is what the notices should say. "It's time for Dhuhr —
/// verify your prayer to unlock" is wrong for a congregation you have to travel
/// to: the useful reminder is that the khutbah is starting and where. This
/// class owns that copy and nothing else, so a change to Friday wording never
/// risks changing when anything fires.
library;

import '../entities/jumuah_profile.dart';

/// The Friday-specific text for each notification the planner emits.
class JumuahNotificationManager {
  const JumuahNotificationManager();

  /// "Jumu'ah in 30 minutes"
  String reminderTitle(int minutes) =>
      "Jumu'ah in $minutes ${minutes == 1 ? 'minute' : 'minutes'}";

  /// Body for a pre-Jumu'ah reminder.
  ///
  /// Names the mosque, because the whole point of the reminder is to get the
  /// user moving toward a specific place. The last rung says apps are about to
  /// lock, since that is the thing that changes behaviour.
  String reminderBody({
    required JumuahProfile profile,
    required int minutes,
    required bool blockingEnabled,
  }) {
    final where = profile.location.displayName;
    if (blockingEnabled && minutes <= 5) {
      return 'Heading to $where? Selected apps lock when Jumu\'ah begins.';
    }
    return 'At $where, ${profile.startsAt.format()}.';
  }

  /// "Jumu'ah has started"
  String startedTitle() => "Jumu'ah has started";

  /// Body at the moment the window opens — the "apps are now locked" notice.
  String startedBody({
    required JumuahProfile profile,
    required bool blockingEnabled,
  }) {
    if (!blockingEnabled) {
      return 'May Allah accept your prayer at ${profile.location.displayName}.';
    }
    return 'Apps are locked until ${profile.endsAt.format()}.';
  }

  /// "Jumu'ah time is ending"
  String endingTitle() => "Jumu'ah time is ending";

  String endingBody({required JumuahProfile profile, required int leadMinutes}) =>
      '$leadMinutes minutes left to confirm your Jumu\'ah at '
      '${profile.location.displayName}.';

  /// "Jumu'ah has ended"
  String endedTitle() => "Jumu'ah has ended";

  /// Body when the window closes — the "apps unlocked" notice.
  ///
  /// Deliberately does not mention qaza. Jumu'ah cannot be made up as Jumu'ah;
  /// someone who misses it prays Dhuhr instead. Offering "pray it as qaza"
  /// would be telling the user something incorrect about their own obligation.
  String endedBody({required bool blockingEnabled}) {
    if (!blockingEnabled) return 'The Jumu\'ah window has closed.';
    return 'Apps are unlocked. If you missed Jumu\'ah, pray Dhuhr instead.';
  }
}

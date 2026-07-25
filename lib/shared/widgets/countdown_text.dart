/// Duration formatting shared across the dashboard and lock screen.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Formats a duration as a countdown.
///
/// Deliberately drops to "12m 04s" under an hour rather than showing
/// "00:12:04". Leading zero hours read as a stopwatch; the goal is for a
/// glance to answer "how long have I got" without parsing.
String formatCountdown(Duration duration) {
  if (duration.isNegative) return 'now';

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
  return '${seconds}s';
}

/// Formats elapsed time in coarse, human terms.
///
/// Takes a context because "3 hours ago" is a sentence, not a number, and the
/// plural rule differs by language — Arabic has six forms where English has
/// two. The ARB carries the rule; this only picks the unit.
String formatElapsed(BuildContext context, Duration duration) {
  final strings = AppLocalizations.of(context);
  if (duration.inMinutes < 1) return strings.countdownJustNow;
  if (duration.inHours < 1) return strings.countdownMinutesAgo(duration.inMinutes);
  if (duration.inDays < 1) return strings.countdownHoursAgo(duration.inHours);
  return strings.countdownDaysAgo(duration.inDays);
}

/// Large countdown display.
class CountdownText extends StatelessWidget {
  const CountdownText({super.key, required this.duration, this.style});

  final Duration duration;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatCountdown(duration),
      style: style ?? Theme.of(context).textTheme.displayLarge,
      // Tabular figures stop the text jittering as digits change width each
      // second, which is very visible at display size.
      textAlign: TextAlign.center,
    );
  }
}

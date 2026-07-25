/// How one authority defines the prayer times.
///
/// Prayer times are not a single algorithm with a parameter. Each authority is
/// a small bundle of decisions: the sun's depression at Fajr, whether Isha is an
/// angle or a fixed interval after Maghrib, whether Maghrib begins at the
/// horizon or after the redness fades, and — separately — an arbitrary numeric
/// id assigned by whichever remote service is asked.
///
/// Before this existed those decisions were spread across three places: an
/// angles map in the calculator, an id map in the AlAdhan provider, and a
/// shadow factor read off the madhab at the call site. Adding an authority
/// meant finding all three, and the failure mode of missing one is silent —
/// times that are subtly wrong rather than absent.
///
/// A strategy holds one authority's whole definition. The registry is the only
/// thing that knows the set, so adding the fourteenth is one entry.
library;

import '../entities/prayer_enums.dart';
import '../usecases/prayer_time_calculator.dart' show MethodParameters;

/// One authority's complete definition.
abstract interface class CalculationStrategy {
  /// The method this strategy answers for.
  CalculationMethod get method;

  /// Solar angles used by the on-device calculator.
  MethodParameters get parameters;

  /// AlAdhan's numeric identifier for this authority.
  ///
  /// Null when the service does not publish this method, in which case a
  /// remote fetch is not attempted and the on-device calculator answers. Not
  /// derivable from anything — it is an arbitrary registry defined by the
  /// service — so it is data carried alongside the angles it corresponds to.
  int? get remoteMethodId;

  /// Whether the remote service can answer for this method at all.
  bool get supportsRemote => remoteMethodId != null;
}

/// A strategy defined entirely by constants.
///
/// Every authority shipped today is of this shape. The interface stays open for
/// one that must compute — a method whose Isha interval lengthens during
/// Ramadan, say, which Umm al-Qura actually does and which a future strategy
/// could express without touching a single consumer.
class _ConstantCalculationStrategy implements CalculationStrategy {
  const _ConstantCalculationStrategy({
    required this.method,
    required this.parameters,
    required this.remoteMethodId,
  });

  @override
  final CalculationMethod method;

  @override
  final MethodParameters parameters;

  @override
  final int? remoteMethodId;

  @override
  bool get supportsRemote => remoteMethodId != null;
}

/// Resolves a calculation method to its definition.
class CalculationRegistry {
  CalculationRegistry(Iterable<CalculationStrategy> strategies)
      : _strategies = {
          for (final strategy in strategies) strategy.method: strategy,
        };

  /// The authorities the app ships with.
  ///
  /// Angles are as published by each authority; the remote ids are AlAdhan's.
  /// Both are pinned by tests, because a transposed digit here produces times
  /// that look plausible and are wrong — the worst kind of error this app can
  /// make.
  factory CalculationRegistry.standard() => CalculationRegistry(const [
        _ConstantCalculationStrategy(
          method: CalculationMethod.muslimWorldLeague,
          parameters: MethodParameters(fajrAngle: 18.0, ishaAngle: 17.0),
          remoteMethodId: 3,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.egyptian,
          parameters: MethodParameters(fajrAngle: 19.5, ishaAngle: 17.5),
          remoteMethodId: 5,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.karachi,
          parameters: MethodParameters(fajrAngle: 18.0, ishaAngle: 18.0),
          remoteMethodId: 1,
        ),
        // Umm al-Qura fixes Isha at 90 minutes after Maghrib (120 in Ramadan).
        _ConstantCalculationStrategy(
          method: CalculationMethod.ummAlQura,
          parameters:
              MethodParameters(fajrAngle: 18.5, ishaIntervalMinutes: 90),
          remoteMethodId: 4,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.dubai,
          parameters: MethodParameters(fajrAngle: 18.2, ishaAngle: 18.2),
          remoteMethodId: 16,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.qatar,
          parameters:
              MethodParameters(fajrAngle: 18.0, ishaIntervalMinutes: 90),
          remoteMethodId: 10,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.kuwait,
          parameters: MethodParameters(fajrAngle: 18.0, ishaAngle: 17.5),
          remoteMethodId: 9,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.moonsightingCommittee,
          parameters: MethodParameters(fajrAngle: 18.0, ishaAngle: 18.0),
          remoteMethodId: 15,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.singapore,
          parameters: MethodParameters(fajrAngle: 20.0, ishaAngle: 18.0),
          remoteMethodId: 11,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.turkey,
          parameters: MethodParameters(fajrAngle: 18.0, ishaAngle: 17.0),
          remoteMethodId: 13,
        ),
        // Tehran also lifts Maghrib off the horizon, to 4.5 degrees.
        _ConstantCalculationStrategy(
          method: CalculationMethod.tehran,
          parameters: MethodParameters(
            fajrAngle: 17.7,
            ishaAngle: 14.0,
            maghribAngle: 4.5,
          ),
          remoteMethodId: 7,
        ),
        _ConstantCalculationStrategy(
          method: CalculationMethod.northAmerica,
          parameters: MethodParameters(fajrAngle: 15.0, ishaAngle: 15.0),
          remoteMethodId: 2,
        ),
        // Ja'fari also lifts Maghrib off the horizon: it begins when the sun's
        // redness fades, at roughly 4 degrees, rather than at sunset.
        _ConstantCalculationStrategy(
          method: CalculationMethod.jafari,
          parameters: MethodParameters(
            fajrAngle: 16.0,
            ishaAngle: 14.0,
            maghribAngle: 4.0,
          ),
          // AlAdhan's "Shia Ithna-Ashari, Leva Institute, Qum".
          remoteMethodId: 0,
        ),
      ]);

  final Map<CalculationMethod, CalculationStrategy> _strategies;

  /// The strategy for [method].
  ///
  /// Falls back to Muslim World League rather than throwing. An unregistered
  /// method is a programming error, but a user whose times are computed by the
  /// most widely used authority is far better served than one looking at a
  /// crash.
  CalculationStrategy forMethod(CalculationMethod method) =>
      _strategies[method] ??
      _strategies[CalculationMethod.muslimWorldLeague]!;

  /// Angles for [method], for the on-device calculator.
  MethodParameters parametersFor(CalculationMethod method) =>
      forMethod(method).parameters;

  /// AlAdhan's id for [method], or null when it cannot answer.
  int? remoteIdFor(CalculationMethod method) =>
      forMethod(method).remoteMethodId;

  /// Every registered authority.
  List<CalculationStrategy> get all => List.unmodifiable(_strategies.values);

  /// A copy with [strategy] replacing whatever answered for its method.
  CalculationRegistry withStrategy(CalculationStrategy strategy) =>
      CalculationRegistry([
        ..._strategies.values.where((s) => s.method != strategy.method),
        strategy,
      ]);
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the property that makes three languages maintainable: they say the
/// same things.
///
/// The failure this prevents is quiet. A key added to English and forgotten in
/// Urdu does not crash, does not warn, and does not fail any other test — an
/// Urdu reader simply sees an English sentence in the middle of their app, and
/// nobody who does not read Urdu will ever notice.
///
/// The ARB files are generated from one table by tool/gen_arb.py, so in normal
/// use these cannot drift. This is the check that the generator was actually
/// run, and that nobody hand-edited one file afterwards.
void main() {
  Map<String, dynamic> load(String language) {
    final file = File('lib/l10n/app_$language.arb');
    // Read outside any test body, so `expect` is not available here — a plain
    // throw reports the same thing and does not depend on the test binding.
    if (!file.existsSync()) throw StateError('${file.path} is missing');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  Set<String> keysOf(Map<String, dynamic> arb) =>
      arb.keys.where((key) => !key.startsWith('@')).toSet();

  final english = load('en');
  final arabic = load('ar');
  final urdu = load('ur');

  final englishKeys = keysOf(english);

  test('English defines a meaningful number of strings', () {
    // A guard against the generator silently producing an empty file, which
    // would make every other assertion here vacuously true.
    expect(englishKeys.length, greaterThan(250));
  });

  for (final entry in {'Arabic': arabic, 'Urdu': urdu}.entries) {
    final name = entry.key;
    final keys = keysOf(entry.value);

    test('$name translates every English string', () {
      expect(
        englishKeys.difference(keys),
        isEmpty,
        reason: '$name is missing these keys',
      );
    });

    test('$name defines nothing English does not', () {
      // An orphan is dead weight at best and, when it is a renamed key, a
      // translation nobody will ever see.
      expect(
        keys.difference(englishKeys),
        isEmpty,
        reason: '$name has keys English does not',
      );
    });

    test('$name leaves no string empty', () {
      final empty = [
        for (final key in keys)
          if ((entry.value[key] as String).trim().isEmpty) key,
      ];
      expect(empty, isEmpty, reason: 'empty $name strings');
    });

    test('$name keeps every placeholder', () {
      // A placeholder dropped in translation renders as literal text — the
      // user sees "{minutes} minutes before" rather than a number.
      final pattern = RegExp(r'\{(\w+)\}');
      final broken = <String>[];

      for (final key in englishKeys) {
        final source = pattern
            .allMatches(english[key] as String)
            .map((m) => m.group(1))
            .toSet();
        final target = pattern
            .allMatches(entry.value[key] as String)
            .map((m) => m.group(1))
            .toSet();
        if (source.difference(target).isNotEmpty ||
            target.difference(source).isNotEmpty) {
          broken.add('$key: expected $source, got $target');
        }
      }

      expect(broken, isEmpty, reason: 'placeholder mismatch in $name');
    });

    test('$name is not simply a copy of English', () {
      // Catches the other half-done state: keys present, values pasted from
      // the template and never translated.
      final identical = [
        for (final key in englishKeys)
          if (english[key] == entry.value[key]) key,
      ];

      // Some are legitimately identical — "Jumu'ah" transliterates the same in
      // Urdu script only sometimes, and proper nouns recur — so this asserts a
      // proportion rather than zero.
      expect(
        identical.length / englishKeys.length,
        lessThan(0.05),
        reason: '${identical.length} $name strings are still English',
      );
    });
  }

  test('every locale declares itself', () {
    expect(english['@@locale'], 'en');
    expect(arabic['@@locale'], 'ar');
    expect(urdu['@@locale'], 'ur');
  });
}

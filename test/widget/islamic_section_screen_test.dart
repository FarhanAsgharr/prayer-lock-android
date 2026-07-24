/// Widget tests for the Islamic section picker.
///
/// The assertions are about respect as much as function: every section is
/// offered, none is ranked above another, what a choice changes is stated
/// rather than applied silently, and a user whose community is not listed can
/// name their own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/config/locale_config.dart';
import 'package:prayer_lock/features/sections/domain/entities/islamic_section.dart';
import 'package:prayer_lock/features/sections/presentation/screens/islamic_section_screen.dart';

Widget _harness({
  required SectionIdentity selected,
  ValueChanged<SectionIdentity>? onSelected,
  ValueChanged<String>? onLabelChanged,
}) =>
    MaterialApp(
      // The picker reads localised strings, so the delegates must be installed
      // exactly as the real app installs them.
      locale: const Locale('en'),
      supportedLocales: LocaleConfig.supportedLocales,
      localizationsDelegates: LocaleConfig.delegates,
      home: Scaffold(
        body: IslamicSectionPicker(
          selected: selected,
          onSelected: onSelected ?? (_) {},
          onLabelChanged: onLabelChanged ?? (_) {},
        ),
      ),
    );

void main() {
  // The list is long; a tall viewport renders it all so assertions are about
  // the screen rather than about scrolling.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 6000);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  testWidgets('offers every section', (tester) async {
    await tester.pumpWidget(_harness(selected: SectionIdentity.fallback));
    await tester.pumpAndSettle();

    for (final section in IslamicSection.values) {
      expect(
        find.text(section.defaultLabel),
        findsWidgets,
        reason: '${section.defaultLabel} is missing from the picker',
      );
    }
  });

  testWidgets('groups sections by family', (tester) async {
    await tester.pumpWidget(_harness(selected: SectionIdentity.fallback));
    await tester.pumpAndSettle();

    for (final family in SectionFamily.values) {
      expect(find.text(family.displayName), findsOneWidget);
    }
  });

  testWidgets('explains what each section implies', (tester) async {
    // Users are entitled to know why the app is about to move their settings.
    await tester.pumpWidget(
      _harness(selected: const SectionIdentity.of(IslamicSection.hanafi)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('twice an object'), findsOneWidget);
  });

  testWidgets('does not present the title "Madhab"', (tester) async {
    await tester.pumpWidget(_harness(selected: SectionIdentity.fallback));
    await tester.pumpAndSettle();

    expect(find.textContaining('Madhab'), findsNothing);
    expect(find.textContaining('madhab'), findsNothing);
  });

  testWidgets('states that nothing here is a ruling', (tester) async {
    await tester.pumpWidget(_harness(selected: SectionIdentity.fallback));
    await tester.pumpAndSettle();

    expect(find.textContaining('religious ruling'), findsOneWidget);
  });

  testWidgets('selecting a section reports the choice', (tester) async {
    SectionIdentity? chosen;
    await tester.pumpWidget(
      _harness(
        selected: SectionIdentity.fallback,
        onSelected: (identity) => chosen = identity,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zaydi'));
    await tester.pumpAndSettle();

    expect(chosen?.section, IslamicSection.zaydi);
  });

  testWidgets('shows the free-text field only after choosing Other',
      (tester) async {
    await tester.pumpWidget(
      _harness(selected: const SectionIdentity.of(IslamicSection.maliki)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your Islamic section'), findsNothing);

    await tester.pumpWidget(_harness(selected: SectionIdentity.fallback));
    await tester.pumpAndSettle();
    expect(find.text('Enter your Islamic section'), findsOneWidget);
  });

  testWidgets('a typed name is reported as it is entered', (tester) async {
    // There is no confirm button, so a name saved only on submit would be lost
    // on back-navigation.
    String? label;
    await tester.pumpWidget(
      _harness(
        selected: SectionIdentity.fallback,
        onLabelChanged: (value) => label = value,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ahmadi');
    await tester.pumpAndSettle();

    expect(label, 'Ahmadi');
  });

  testWidgets('a named section is shown by its own name', (tester) async {
    await tester.pumpWidget(
      _harness(selected: SectionIdentity.custom('My community')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('My community'), findsWidgets);
  });

  testWidgets('an unchosen section prompts rather than asserting one',
      (tester) async {
    await tester.pumpWidget(_harness(selected: SectionIdentity.fallback));
    await tester.pumpAndSettle();

    expect(find.text('Name your section above'), findsOneWidget);
  });

  testWidgets('summarises what the selection sets', (tester) async {
    await tester.pumpWidget(
      _harness(selected: const SectionIdentity.of(IslamicSection.twelver)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected: Twelver (Ithna Ashari)'), findsOneWidget);
    expect(find.text('Prayer times'), findsOneWidget);
    expect(find.text('Asr timing'), findsOneWidget);
    expect(find.text('Prayer grouping'), findsOneWidget);
    // The suggestion is disclosed, not hidden.
    expect(find.text('Combine both pairs'), findsOneWidget);
  });

  testWidgets('says the defaults remain editable', (tester) async {
    await tester.pumpWidget(
      _harness(selected: const SectionIdentity.of(IslamicSection.ismaili)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('change any of these'), findsOneWidget);
  });
}

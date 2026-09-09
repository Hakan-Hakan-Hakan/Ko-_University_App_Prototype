import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:flutter_application_1/models/app_admin.dart';
import 'package:flutter_application_1/models/club.dart';
import 'package:flutter_application_1/models/content_audience.dart';
import 'package:flutter_application_1/models/event.dart';
import 'package:flutter_application_1/screens/create_event_screen.dart';
import 'package:flutter_application_1/services/app_strings.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/content_audience_store.dart';
import 'package:flutter_application_1/services/content_store.dart';
import 'package:flutter_application_1/services/content_visibility.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/supabase_event_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The event wizard's edit branch rebuilds its `Event` field by field, so a new
/// field that is not threaded through it is silently reset to its default on the
/// next save. These lock the audience into that branch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('audience_event_edit_');
    Hive.init(tempDir.path);
    await contentStore.initialize();
    await contentAudienceStore.initialize();
  });

  tearDown(() async {
    await authService.logout();
    contentAudienceStore.clearSessionState();
    clubs.clear();
    events.clear();
  });

  tearDownAll(() {
    // Deliberately no `Hive.close()`. The wizard's save path fires a `box.put`
    // from inside the fake-async zone, and closing waits on a future that can
    // never complete outside it — a 12-minute hang. The design suites that
    // touch contentStore drop the close for the same reason.
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> openEditor(WidgetTester tester, Event event) async {
    // The details step scrolls and builds lazily, so the audience cell — the
    // last thing on it — is not in the tree on the default 800x600 surface.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateEventScreen(
                        existing: event,
                        eventService: _FakeEventService(),
                      ),
                    ),
                  ),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// The details step is a `ListView`, so its last child does not exist until
  /// it is scrolled towards. Guessing a tall enough surface is fragile; this is
  /// not.
  Future<Finder> revealAudienceCell(WidgetTester tester) async {
    final cell = find.byKey(const ValueKey('event-wizard-audience'));
    await tester.scrollUntilVisible(
      cell,
      300,
      // `.first` because the description field is itself scrollable, and
      // scrollUntilVisible demands exactly one Scrollable.
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('event-wizard-step-details')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    return cell;
  }

  Future<void> saveFromPreview(WidgetTester tester) async {
    for (final cta in [
      S.eventWizardNextStep,
      S.eventWizardNextStep,
      S.eventWizardPreviewBadge,
    ]) {
      await tester.tap(find.text(cta));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text(S.eventWizardSaveChanges));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  ({Club club, Event event}) seed(ContentAudience audience) {
    final club = Club(
      id: 'club-audience-edit',
      name: 'Test Club',
      description: '',
      adminUserIds: const [],
    );
    final event = Event(
      id: 'event-audience-edit',
      clubId: club.id,
      title: 'Original event',
      description: 'Audience edit regression fixture',
      dateTime: DateTime(2026, 9, 1, 12),
      endTime: DateTime(2026, 9, 1, 14),
      location: 'Campus',
      attendeeUserIds: const [],
      audience: audience,
    );
    clubs.add(club);
    events.add(event);
    authService.setClubAdmin(
      AppAdmin(
        id: club.id,
        name: club.name,
        email: 'club@ku.edu.tr',
        password: '',
      ),
    );
    return (club: club, event: event);
  }

  testWidgets('the wizard offers the audience cell on the details step', (
    tester,
  ) async {
    seed(ContentAudience.everyone);
    await openEditor(tester, events.single);

    final cell = await revealAudienceCell(tester);
    expect(cell, findsOneWidget);
    expect(
      find.descendant(of: cell, matching: find.text(S.audienceEveryone)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an existing restricted event opens on its own tier', (
    tester,
  ) async {
    seed(ContentAudience.board);
    await openEditor(tester, events.single);

    final cell = await revealAudienceCell(tester);
    expect(
      find.descendant(of: cell, matching: find.text(S.audienceBoard)),
      findsOneWidget,
      reason: 'an edit must open on the tier the event already has',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving an edit without touching the picker keeps the tier', (
    tester,
  ) async {
    seed(ContentAudience.followers);
    await openEditor(tester, events.single);

    await tester.enterText(find.byType(TextField).first, 'Edited in wizard');
    await saveFromPreview(tester);

    expect(events.single.title, 'Edited in wizard');
    // The regression: a hand-rebuilt Event would have dropped this back to
    // everyone and quietly made a followers-only event public.
    expect(events.single.audience, ContentAudience.followers);
    expect(audienceForEvent(events.single), ContentAudience.followers);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the tier in the sheet is persisted on save', (
    tester,
  ) async {
    seed(ContentAudience.everyone);
    await openEditor(tester, events.single);

    final cell = await revealAudienceCell(tester);
    tester.widget<GestureDetector>(cell).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('content-audience-sheet')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('content-audience-option-board')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    await saveFromPreview(tester);

    expect(events.single.audience, ContentAudience.board);
    expect(audienceForEvent(events.single), ContentAudience.board);
    expect(tester.takeException(), isNull);
  });
}

class _FakeEventService extends SupabaseEventService {
  @override
  Future<Event> updateEvent(Event event, {String? previousImagePath}) async {
    return event;
  }
}

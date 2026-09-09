import 'dart:io';

import 'package:flutter_application_1/models/content_audience.dart';
import 'package:flutter_application_1/services/content_audience_store.dart';
import 'package:flutter_application_1/services/guest_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The store is what makes the audience survive a content refresh, so what it
/// keeps and what it refuses to keep both matter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('content_audience_store_');
    Hive.init(tempDir.path);
    await contentAudienceStore.initialize();
  });

  setUp(() {
    guestSession.end();
    contentAudienceStore.clearSessionState();
  });

  tearDown(() {
    guestSession.end();
    contentAudienceStore.clearSessionState();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('an unknown id has no override', () {
    expect(contentAudienceStore.audienceFor('never-set'), isNull);
  });

  test('a restricted tier round-trips', () async {
    await contentAudienceStore.setAudience('p1', ContentAudience.board);
    expect(contentAudienceStore.audienceFor('p1'), ContentAudience.board);
    await contentAudienceStore.setAudience('p1', ContentAudience.followers);
    expect(contentAudienceStore.audienceFor('p1'), ContentAudience.followers);
  });

  test('everyone is removed rather than stored', () async {
    await contentAudienceStore.setAudience('p2', ContentAudience.board);
    await contentAudienceStore.setAudience('p2', ContentAudience.everyone);
    // Null, not ContentAudience.everyone — public is the default everywhere, so
    // a row saying "no restriction" would carry no information.
    expect(contentAudienceStore.audienceFor('p2'), isNull);
  });

  test('seedAudiences applies a batch and drops the public entries', () {
    contentAudienceStore.seedAudiences({
      'p3': ContentAudience.board,
      'p4': ContentAudience.followers,
      'p5': ContentAudience.everyone,
    });
    expect(contentAudienceStore.audienceFor('p3'), ContentAudience.board);
    expect(contentAudienceStore.audienceFor('p4'), ContentAudience.followers);
    expect(contentAudienceStore.audienceFor('p5'), isNull);
  });

  test('pruneMissing drops entries whose content is gone', () async {
    await contentAudienceStore.setAudience('p6', ContentAudience.board);
    await contentAudienceStore.setAudience('p7', ContentAudience.board);
    contentAudienceStore.pruneMissing(const ['p6']);
    expect(contentAudienceStore.audienceFor('p6'), ContentAudience.board);
    expect(contentAudienceStore.audienceFor('p7'), isNull);
  });

  test('a guest write stays in memory and never reaches the box', () async {
    guestSession.begin();
    await contentAudienceStore.setAudience('guest-p', ContentAudience.board);
    // Readable during the session…
    expect(contentAudienceStore.audienceFor('guest-p'), ContentAudience.board);
    guestSession.end();
    // …and gone once the joyride ends, so it cannot leak into a real account.
    contentAudienceStore.clearSessionState();
    expect(contentAudienceStore.audienceFor('guest-p'), isNull);
    final box = Hive.box<dynamic>('content_audience_v1');
    final stored = box.get('audiences');
    expect(
      stored is Map ? stored.containsKey('guest-p') : false,
      isFalse,
      reason: 'guest audiences must never be persisted',
    );
  });

  test('a stored everyone from an older build is ignored on load', () async {
    final box = Hive.box<dynamic>('content_audience_v1');
    await box.put('audiences', {
      'legacy-public': 'everyone',
      'legacy-board': 'board',
      'legacy-garbage': 'not-a-tier',
    });
    // Force a re-read the way a cold start would.
    contentAudienceStore.clearSessionState();
    final raw = box.get('audiences') as Map;
    contentAudienceStore.seedAudiences({
      for (final entry in raw.entries)
        entry.key.toString(): contentAudienceFromWire(entry.value),
    });
    expect(contentAudienceStore.audienceFor('legacy-board'),
        ContentAudience.board);
    expect(contentAudienceStore.audienceFor('legacy-public'), isNull);
    // An unknown tier decodes as public, so it is dropped too — never hidden.
    expect(contentAudienceStore.audienceFor('legacy-garbage'), isNull);
  });
}

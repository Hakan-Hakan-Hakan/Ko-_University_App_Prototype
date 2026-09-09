import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flutter_application_1/models/chat_message.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/chat_store.dart';
import 'package:flutter_application_1/services/checkin_store.dart';
import 'package:flutter_application_1/services/content_store.dart';
import 'package:flutter_application_1/services/guest_session.dart';
import 'package:flutter_application_1/services/guest_world.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/poll_store.dart';
import 'package:flutter_application_1/services/post_like_helper.dart';
import 'package:flutter_application_1/services/theme_service.dart';
import 'package:flutter_application_1/services/user_prefs_service.dart';
import 'package:flutter_application_1/services/user_state.dart';
import 'package:flutter_application_1/services/view_tracker.dart';

/// The promise the whole feature rests on: a guest joyride leaves nothing on
/// the device. Every store the app persists through is opened against a fresh
/// temporary Hive directory, snapshotted, driven through the actions a guest
/// can perform, and then checked to be byte-for-byte unchanged.
void main() {
  /// Every Hive box the app writes user content or preferences into.
  const boxNames = <String>[
    'content_v1',
    'chat_v1',
    'user_prefs',
    'view_tracker_v1',
    'poll_votes_v1',
    'event_checkins_v1',
    'theme_box',
  ];

  Map<String, Map<String, String>> snapshot() {
    final out = <String, Map<String, String>>{};
    for (final name in boxNames) {
      if (!Hive.isBoxOpen(name)) continue;
      final box = Hive.box<dynamic>(name);
      out[name] = {
        for (final key in box.keys) key.toString(): '${box.get(key)}',
      };
    }
    return out;
  }

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('guest_no_persist_');
    Hive.init(tempDir.path);
    addTearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // Opened before any guest session begins, exactly as bootstrap does, so
    // the stores' own initialization is not itself under the guest gate.
    await contentStore.initialize();
    await chatStore.initialize();
    await userPrefsService.initialize();
    await viewTracker.initialize();
    await pollStore.initialize();
    await checkinStore.initialize();
    await themeService.initialize();
    for (final name in boxNames) {
      if (!Hive.isBoxOpen(name)) await Hive.openBox<dynamic>(name);
    }
  });

  test('no guest action reaches disk', () async {
    final before = snapshot();
    expect(before.keys, containsAll(boxNames));

    guestSession.begin();
    seedGuestWorld();
    authService.enterGuestSession();

    // ── the things a guest can do ──
    await togglePostLike('guest_post_3');
    userState.toggleFollow('guest_club_entre');
    userState.toggleFollowUser('guest_u_burak');
    userState.toggleSave('guest_post_9');
    userState.togglePinnedPost('guest_post_1');
    userState.setBio(kGuestUserId, 'Edited during the joyride');
    await userPrefsService.save(kGuestUserId);
    await userPrefsService.savePinnedPosts();
    await userPrefsService.saveClubDescription(
      kGuestBoardClubId,
      'Edited during the joyride',
    );

    // Creating content: the local path the app already takes when there is no
    // Supabase client (SupabasePostService.createPost returns a local post).
    newsPosts.insert(
      0,
      newsPosts.first,
    );
    await contentStore.saveNewsPosts();
    await contentStore.saveEvents();
    await contentStore.saveLikes();
    contentStore.scheduleSave('posts');
    await contentStore.flushPendingSaves();

    // Chat
    chatStore.sendMessage(
      threadId: ChatStore.dmThreadId(kGuestUserId, 'guest_u_selin'),
      senderId: kGuestUserId,
      content: 'Sent during the joyride',
      kind: ChatMessageKind.text,
    );
    chatStore.scheduleSave();
    await chatStore.saveAll();

    // Views, votes, check-ins
    viewTracker.recordView('guest_post_2', kGuestUserId);
    await pollStore.vote(
      post: newsPosts.firstWhere((post) => post.id == 'guest_post_5'),
      userId: kGuestUserId,
      optionIndex: 1,
    );
    await checkinStore.toggle(eventId: 'guest_event_1', userId: 'guest_u_can');

    // Preferences
    await themeService.setDark(true, persistToAccount: false);

    // Notifications
    userState.markNotificationsRead(userState.dynamicNotifications);

    // Anything debounced would still be in flight; give it more than the 1s
    // window the stores coalesce on.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await contentStore.saveAll(userState.dynamicNotifications);
    await chatStore.saveAll();

    expect(
      snapshot(),
      before,
      reason: 'a guest action was written to a Hive box',
    );

    // And the teardown itself must not write either.
    await authService.logout();
    expect(
      snapshot(),
      before,
      reason: 'guest teardown wrote to a Hive box',
    );
    expect(guestSession.isActive, isFalse);
    expect(guestWorldIsSeeded, isFalse);
  });

  test('gates report success, so optimistic updates are never rolled back', () async {
    guestSession.begin();
    seedGuestWorld();
    authService.enterGuestSession();
    addTearDown(() async {
      await authService.logout();
    });

    // togglePostLike and handleFollowTap both undo their optimistic update in
    // a catch block. A gate that threw instead of reporting success would make
    // every like and follow visibly bounce back.
    expect(userState.isLiked('guest_post_1'), isFalse);
    await togglePostLike('guest_post_1');
    expect(
      userState.isLiked('guest_post_1'),
      isTrue,
      reason: 'the like was rolled back, so a guest gate threw',
    );

    await togglePostLike('guest_post_1');
    expect(userState.isLiked('guest_post_1'), isFalse);

    // The counter moves with it, so the number under the heart is not frozen.
    // `guest_post_4` is deliberately one the seed world does not pre-like.
    expect(userState.isLiked('guest_post_4'), isFalse);
    final before = postLikeCount('guest_post_4');
    await togglePostLike('guest_post_4');
    expect(postLikeCount('guest_post_4'), before + 1);
    await togglePostLike('guest_post_4');
    expect(postLikeCount('guest_post_4'), before);
  });

  test('logout restores an empty slate for the next account', () async {
    guestSession.begin();
    seedGuestWorld();
    authService.enterGuestSession();

    expect(newsPosts, isNotEmpty);
    expect(authService.currentUser, isNotNull);

    await authService.logout();

    expect(authService.currentUser, isNull);
    expect(authService.currentAdmin, isNull);
    expect(newsPosts, isEmpty);
    expect(clubs, isEmpty);
    expect(users, isEmpty);
    expect(userState.followedClubIds, isEmpty);
    expect(
      chatStore.messagesFor(ChatStore.dmThreadId(kGuestUserId, 'guest_u_selin')),
      isEmpty,
    );
    expect(pollStore.myVote('guest_post_5', kGuestUserId), isNull);
  });
}

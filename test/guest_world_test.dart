import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flutter_application_1/models/chat_message.dart';
import 'package:flutter_application_1/services/account_switcher_service.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/chat_store.dart';
import 'package:flutter_application_1/services/guest_session.dart';
import 'package:flutter_application_1/services/guest_world.dart';
import 'package:flutter_application_1/services/locale_service.dart';
import 'package:flutter_application_1/services/club_admin_access.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/people_service.dart';
import 'package:flutter_application_1/services/user_state.dart';

/// Every club the guest is joined to and therefore has a full room for.
/// Mirrors `_guestFollowedClubIds`, which is private to the seed world — and
/// that is every seeded club, so the length check below is part of the point.
const _joinedClubIds = [
  kGuestBoardClubId,
  'guest_club_robotics',
  'guest_club_photo',
  'guest_club_film',
  'guest_club_hiking',
  'guest_club_music',
  'guest_club_volunteer',
  'guest_club_entre',
];

/// The fabricated campus behind Guest Login.
void main() {
  // ChatStore uses its Hive box as an "initialized" sentinel — `messagesFor`
  // and friends return empty while it is null — so guest mode keeps the box
  // open and gates the writes instead. Bootstrap opens it in the real app;
  // this stands in for that. Opened before any guest session begins, so the
  // store's own initialization is not itself gated.
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('guest_world_test_');
    Hive.init(tempDir.path);
    addTearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    await chatStore.initialize();
  });

  setUp(() {
    // `seedGuestWorld` must run inside a guest session: the teardown it starts
    // with would otherwise be allowed to persist an empty snapshot.
    guestSession.begin();
  });

  tearDown(() async {
    clearGuestWorld();
    guestSession.end();
    await localeService.setLanguage('en');
  });

  test('seeds every registry the app reads from', () {
    expect(users, isEmpty, reason: 'nothing is seeded at import time');

    seedGuestWorld();

    expect(guestWorldIsSeeded, isTrue);
    expect(users, isNotEmpty);
    expect(clubs, isNotEmpty);
    expect(events, isNotEmpty);
    expect(newsPosts, isNotEmpty);
    expect(comments, isNotEmpty);
    expect(likes, isNotEmpty);
    expect(shares, isNotEmpty);
    expect(subscriptions, isNotEmpty);
    expect(notifications, isNotEmpty);

    // The rails the feed falls back to when Feed v2 has not loaded.
    expect(peopleService.cachedPeople, isNotEmpty);
    expect(userState.followedClubIds, isNotEmpty);
    expect(userState.dynamicNotifications, isNotEmpty);

    // Engagement numbers, so counters are not all zero on a cold demo.
    expect(supabaseClubMemberCounts, isNotEmpty);
    expect(supabasePostLikeCounts, isNotEmpty);
    expect(supabaseEventRsvpCounts, isNotEmpty);
  });

  test('every seeded id is guest-prefixed and survives both purge sweeps', () {
    seedGuestWorld();

    final ids = <String>[
      ...users.map((u) => u.id),
      ...clubs.map((c) => c.id),
      ...events.map((e) => e.id),
      ...newsPosts.map((p) => p.id),
      ...comments.map((c) => c.id),
      ...likes.map((l) => l.id),
      ...shares.map((s) => s.id),
      ...subscriptions.map((s) => s.id),
      ...notifications.map((n) => n.id),
    ];
    expect(ids, isNotEmpty);

    for (final id in ids) {
      expect(
        id.startsWith(kGuestIdPrefix),
        isTrue,
        reason: '$id is not prefixed with $kGuestIdPrefix',
      );
    }

    // Two startup migrations delete rows shaped like the legacy fixtures this
    // repo removed. A seed world matching any of these shapes would be eaten
    // silently on the next launch:
    //   ContentStore._removeLegacyFixtures -> ^n\d+$, ^ev\d+$, ^u\d+$
    //   ChatStore._removeMockChatData      -> seed_dm_*, seed_club_*, ^u\d+$
    final legacyShapes = [
      RegExp(r'^u\d+$'),
      RegExp(r'^n\d+$'),
      RegExp(r'^ev\d+$'),
    ];
    for (final id in ids) {
      for (final shape in legacyShapes) {
        expect(
          shape.hasMatch(id),
          isFalse,
          reason: '$id matches the purged legacy shape ${shape.pattern}',
        );
      }
      expect(id.startsWith('seed_dm_'), isFalse, reason: id);
      expect(id.startsWith('seed_club_'), isFalse, reason: id);
    }
  });

  test('the guest is a student who sits on one club board', () {
    seedGuestWorld();
    authService.enterGuestSession();
    addTearDown(authService.logout);

    // Roughly forty write affordances across the app are gated on
    // isStudentSession; anything else would make the tour read-only.
    expect(authService.isStudentSession, isTrue);
    expect(authService.currentUser?.id, kGuestUserId);
    expect(authService.currentAdmin, isNull);

    // Board membership on exactly one club is what surfaces the club-admin
    // point of view in the account switcher.
    final boardClubs = clubs.where(
      (club) => club.boardMemberIds.contains(kGuestUserId),
    );
    expect(boardClubs.map((c) => c.id), [kGuestBoardClubId]);
    expect(
      clubs.firstWhere((c) => c.id == kGuestBoardClubId).boardMemberTitles,
      contains(kGuestUserId),
    );
  });

  test('club rooms are open because following is membership', () {
    seedGuestWorld();

    // ChatStore.canAccessThread treats `userState.isFollowing(clubId)` as club
    // membership, so this is what unlocks the board and chat lanes.
    expect(userState.isFollowing(kGuestBoardClubId), isTrue);
    expect(
      chatStore.messagesFor(ChatStore.clubThreadId(kGuestBoardClubId)),
      isNotEmpty,
    );
  });

  test('every followed club has a populated room, not just the board one', () {
    seedGuestWorld();

    // A joyride that only ever shows one club room makes the Clubs tab of the
    // inbox look broken, so each club the guest follows carries a conversation.
    for (final clubId in _joinedClubIds) {
      expect(
        userState.isFollowing(clubId),
        isTrue,
        reason: '$clubId must be followed or its room is inaccessible',
      );
      expect(
        chatStore.messagesFor(ChatStore.clubThreadId(clubId)),
        isNotEmpty,
        reason: '$clubId has no seeded messages',
      );
      expect(
        chatStore.canAccessThread(
          ChatStore.clubThreadId(clubId),
          kGuestUserId,
        ),
        isTrue,
      );
    }
  });

  test('the guest is joined to every club, so nothing shows Join', () {
    seedGuestWorld();

    // The joyride is a demo: it has to open past every Join button, or the
    // visitor's first act is pressing one on a club they know nothing about.
    // Joining is also what unlocks all three chat lanes, so a club left out
    // would render as a room the guest cannot open.
    expect(
      _joinedClubIds,
      hasLength(clubs.length),
      reason: 'a club was seeded that this test does not know about',
    );
    for (final club in clubs) {
      expect(
        userState.isFollowing(club.id),
        isTrue,
        reason: '${club.id} still shows a Join button',
      );
      expect(
        chatStore.messagesFor(ChatStore.clubThreadId(club.id)),
        isNotEmpty,
        reason: '${club.id} is joined but opens as an empty room',
      );
    }
  });

  test('each joined club has a Direct thread with its own messages', () {
    seedGuestWorld();

    // The Direct lane reads club-inbox conversations, which only ever arrive
    // from Supabase — without seeding them the lane is empty in guest mode no
    // matter how much club chat exists.
    for (final clubId in _joinedClubIds) {
      final inbox = chatStore
          .threadsFor(kGuestUserId)
          .where((t) => t.isClubInbox && t.clubId == clubId)
          .toList();
      expect(
        inbox,
        hasLength(1),
        reason: '$clubId has no direct thread for the guest',
      );
      expect(inbox.single.lastMessage, isNotNull);

      final messages = chatStore.messagesFor(inbox.single.threadId);
      expect(messages, hasLength(2));
      // The guest asks, and the club answers as the club rather than as the
      // board member who typed it.
      expect(messages.first.senderId, kGuestUserId);
      expect(messages.first.senderClubId, isNull);
      expect(messages.last.senderClubId, clubId);
    }
  });

  test('each club room carries both announcements and ordinary chat', () {
    seedGuestWorld();

    // The Board lane is exactly the announcement-kind messages, so a room with
    // none renders an empty Board however busy its chat is.
    for (final clubId in _joinedClubIds) {
      final messages = chatStore.messagesFor(ChatStore.clubThreadId(clubId));
      expect(
        messages.where((m) => m.kind == ChatMessageKind.announcement),
        isNotEmpty,
        reason: '$clubId has no Board notice',
      );
      expect(
        messages.where((m) => m.kind != ChatMessageKind.announcement),
        isNotEmpty,
        reason: '$clubId has no ordinary chat',
      );
    }
  });

  test('the guest can write only in the club they are on the board of', () {
    seedGuestWorld();

    // The read-only composer is the point of seeding rooms the guest merely
    // follows — posting in a club channel is reserved for its board.
    expect(
      chatStore.canWriteClubThread(
        ChatStore.clubThreadId(kGuestBoardClubId),
        kGuestUserId,
      ),
      isTrue,
    );
    for (final clubId in _joinedClubIds.where(
      (id) => id != kGuestBoardClubId,
    )) {
      expect(
        chatStore.canWriteClubThread(
          ChatStore.clubThreadId(clubId),
          kGuestUserId,
        ),
        isFalse,
        reason: 'the guest is not on $clubId\'s board',
      );
    }
  });

  test('club-authored messages are attributed to their own club', () {
    seedGuestWorld();

    // Each channel has its own board voice, so a photography announcement must
    // not come out under the debate club's name.
    final photo = chatStore.messagesFor(
      ChatStore.clubThreadId('guest_club_photo'),
    );
    final announcement = photo.firstWhere(
      (m) => m.id == 'guest_m_photo_1',
    );
    expect(announcement.senderClubId, 'guest_club_photo');

    // And a plain member reply stays attributed to the member.
    final reply = photo.firstWhere((m) => m.id == 'guest_m_photo_3');
    expect(reply.senderClubId, isNull);
  });

  test('seeds direct, group and club conversations', () {
    seedGuestWorld();

    final dm = ChatStore.dmThreadId(kGuestUserId, 'guest_u_selin');
    expect(chatStore.messagesFor(dm), isNotEmpty);
    expect(
      chatStore.messagesFor(ChatStore.groupThreadId('guest_group_board')),
      isNotEmpty,
    );
  });

  test('mutual follows exist, so attendee names are visible', () {
    seedGuestWorld();

    // attendeeVisibilityFor narrows an event's guest list to
    // followedUserIds ∩ peopleService.cachedFollowerIds.
    final mutual = userState.followedUserIds.intersection(
      peopleService.cachedFollowerIds,
    );
    expect(mutual, isNotEmpty);

    // The profile's Followers/Following stats read the per-user maps rather
    // than that flat set, so both halves have to be seeded or the demo profile
    // reads "0 followers".
    expect(peopleService.followersFor(kGuestUserId), isNotEmpty);
    expect(peopleService.followingFor(kGuestUserId), isNotEmpty);
  });

  test('imagery is photographs or built-in gradients, never a local path', () {
    seedGuestWorld();

    final paths = <String?>[
      ...newsPosts.map((p) => p.imagePath),
      ...events.map((e) => e.imagePath),
      ...clubs.map((c) => c.logoUrl),
    ].whereType<String>().toList();

    expect(paths, isNotEmpty);
    for (final path in paths) {
      // Either a remote photograph, or the `tpl:N` gradient the row declares
      // as its offline fallback. A device file path would be a bug: nothing in
      // the seed world exists on the visitor's disk.
      expect(
        path.startsWith('https://') || path.startsWith('tpl:'),
        isTrue,
        reason: path,
      );
    }

    // Every club gets a logo, and every event a cover.
    expect(clubs.where((c) => (c.logoUrl ?? '').isEmpty), isEmpty);
    expect(events.where((e) => (e.imagePath ?? '').isEmpty), isEmpty);

    // The students keep initials avatars rather than borrowing a real face.
    expect(userState.remotePhotoUrls, isEmpty);
    expect(userState.profilePhotoPaths, isEmpty);
  });

  test('a language flip rewrites the copy but keeps interaction state', () async {
    await localeService.setLanguage('en');
    seedGuestWorld();

    final post = newsPosts.firstWhere((p) => p.id == 'guest_post_1');
    final englishContent = post.content;
    final englishClubDescription = clubForId(kGuestBoardClubId)!.description;

    // Interaction state the guest would lose if ids were not deterministic.
    userState.toggleLike('guest_post_5');
    final likedBefore = Set<String>.of(userState.likedPostIds);
    final savedBefore = Set<String>.of(userState.savedPostIds);
    final followedBefore = Set<String>.of(userState.followedClubIds);

    await localeService.setLanguage('tr');

    final turkish = newsPosts.firstWhere((p) => p.id == 'guest_post_1');
    expect(turkish.content, isNot(englishContent));
    expect(clubForId(kGuestBoardClubId)!.description,
        isNot(englishClubDescription));

    // Same ids, so nothing the guest did is orphaned.
    expect(userState.likedPostIds, likedBefore);
    expect(userState.savedPostIds, savedBefore);
    expect(userState.followedClubIds, followedBefore);
    expect(newsPosts.where((p) => p.id == 'guest_post_1'), hasLength(1));
  });

  test('the club-admin point of view is reachable and switching succeeds',
      () async {
    seedGuestWorld();
    authService.enterGuestSession();
    addTearDown(() async {
      accountSwitcherService.clear();
      await authService.logout();
    });

    await accountSwitcherService.prepare();

    // The switcher offers exactly the club the guest sits on the board of.
    expect(
      accountSwitcherService.availableClubs.map((c) => c.id),
      [kGuestBoardClubId],
    );
    expect(accountSwitcherService.hasSwitchableAccounts, isTrue);
    expect(accountSwitcherService.isClubAccountActive, isFalse);

    final club = clubForId(kGuestBoardClubId)!;
    // `select` returns false on any write failure, so this also pins that the
    // guest path skips the `club_account_contexts` upsert rather than tripping
    // over it.
    final switched = await accountSwitcherService.select(
      SwitchableAccount.club(club: club),
    );

    expect(switched, isTrue);
    expect(accountSwitcherService.isClubAccountActive, isTrue);
    expect(accountSwitcherService.activeClub?.id, kGuestBoardClubId);
    // This is the predicate the event/settings/board surfaces gate on.
    expect(currentAccountManagesClubId(kGuestBoardClubId), isTrue);

    // And back to the student POV.
    final back = await accountSwitcherService.select(
      SwitchableAccount.personal(
        id: kGuestUserId,
        name: authService.currentUser!.name,
      ),
    );
    expect(back, isTrue);
    expect(accountSwitcherService.isClubAccountActive, isFalse);
  });

  test('events land on their named weekday at a sensible hour', () {
    seedGuestWorld();

    final debate = events.firstWhere((e) => e.id == 'guest_event_1');
    final walk = events.firstWhere((e) => e.id == 'guest_event_3');
    final screening = events.firstWhere((e) => e.id == 'guest_event_8');

    // Titles name a weekday, so the dates have to agree with them whenever the
    // demo happens to be opened.
    expect(debate.dateTime.weekday, DateTime.thursday);
    expect(screening.dateTime.weekday, DateTime.tuesday);
    expect(walk.dateTime.weekday, DateTime.saturday);

    // And at a plausible time of day rather than "now plus N hours".
    expect(debate.dateTime.hour, 18);
    expect(screening.dateTime.hour, 19);
    expect(walk.dateTime.hour, 7);

    // Upcoming events are in the future; the two past ones are behind us.
    final now = DateTime.now();
    for (final event in events.where((e) => !e.id.contains('past'))) {
      expect(
        event.dateTime.isAfter(now),
        isTrue,
        reason: '${event.id} is not upcoming',
      );
      expect(event.endTime.isAfter(event.dateTime), isTrue);
    }
    for (final event in events.where((e) => e.id.contains('past'))) {
      expect(event.dateTime.isBefore(now), isTrue, reason: event.id);
    }
  });

  test('entering in the app order keeps the seeded conversations', () {
    // The order `_onGuestLogin` uses: flag, identity, then content.
    // `enterGuestSession` crosses an auth boundary and so clears ChatStore;
    // seeding before it would have that teardown wipe these chats out again.
    authService.enterGuestSession();
    seedGuestWorld();
    addTearDown(authService.logout);

    final dm = ChatStore.dmThreadId(kGuestUserId, 'guest_u_selin');
    expect(chatStore.messagesFor(dm), isNotEmpty);
    expect(
      chatStore.messagesFor(ChatStore.clubThreadId(kGuestBoardClubId)),
      isNotEmpty,
    );

    // And the inbox actually lists them: direct threads, the group, and the
    // club rooms the guest follows.
    final threads = chatStore.threadsFor(kGuestUserId);
    expect(threads.where((t) => t.peerId != null), hasLength(3));
    expect(threads.where((t) => t.isGroup), hasLength(1));
    expect(
      threads.where((t) => t.threadId.startsWith('club:')),
      hasLength(_joinedClubIds.length),
    );
    // Plus the guest's own thread with each of those clubs — the Direct lane.
    expect(
      threads.where((t) => t.isClubInbox),
      hasLength(_joinedClubIds.length),
    );
  });

  test('the guest profile is labelled as a guest, in both languages', () async {
    await localeService.setLanguage('en');
    seedGuestWorld();
    authService.enterGuestSession();
    addTearDown(authService.logout);

    // Not a fictional student's name: a visitor should see at a glance that
    // this profile is the demo account.
    expect(guestSessionUser().name, 'Guest 1#');
    expect(authService.currentUser?.name, 'Guest 1#');
    final me = users.firstWhere((user) => user.id == kGuestUserId);
    expect(me.name, 'Guest 1#');
    // Home greets on the first word, so the header reads "Hi, Guest".
    expect(me.name.split(' ').first, 'Guest');
    expect(me.email, 'guest@guest.invalid');

    await localeService.setLanguage('tr');

    // The identifier is the same in both languages, including the name already
    // baked into the live session.
    expect(
      users.firstWhere((user) => user.id == kGuestUserId).name,
      'Guest 1#',
    );
    expect(authService.currentUser?.name, 'Guest 1#');

    // The other students are fictional people; their names are not copy.
    expect(
      users.firstWhere((user) => user.id == 'guest_u_selin').name,
      'Selin Korkmaz',
    );
  });

  test('clearing leaves nothing behind', () {
    seedGuestWorld();
    expect(users, isNotEmpty);

    clearGuestWorld();

    expect(guestWorldIsSeeded, isFalse);
    expect(users, isEmpty);
    expect(clubs, isEmpty);
    expect(events, isEmpty);
    expect(newsPosts, isEmpty);
    expect(comments, isEmpty);
    expect(likes, isEmpty);
    expect(shares, isEmpty);
    expect(subscriptions, isEmpty);
    expect(notifications, isEmpty);
    expect(supabaseClubMemberCounts, isEmpty);
    expect(supabasePostLikeCounts, isEmpty);
    expect(supabaseEventRsvpCounts, isEmpty);

    expect(peopleService.cachedPeople, isEmpty);
    expect(userState.followedClubIds, isEmpty);
    expect(userState.followedUserIds, isEmpty);
    expect(userState.likedPostIds, isEmpty);
    expect(userState.savedPostIds, isEmpty);
    expect(userState.dynamicNotifications, isEmpty);
    expect(userState.bios, isEmpty);
    expect(
      chatStore.messagesFor(ChatStore.clubThreadId(kGuestBoardClubId)),
      isEmpty,
    );
  });
}

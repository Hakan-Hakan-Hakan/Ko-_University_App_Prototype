import 'dart:io';

import 'package:flutter_application_1/models/app_admin.dart';
import 'package:flutter_application_1/models/club.dart';
import 'package:flutter_application_1/models/content_audience.dart';
import 'package:flutter_application_1/models/event.dart';
import 'package:flutter_application_1/models/news_post.dart';
import 'package:flutter_application_1/models/user.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/services/content_audience_store.dart';
import 'package:flutter_application_1/services/content_visibility.dart';
import 'package:flutter_application_1/services/mock_data.dart';
import 'package:flutter_application_1/services/user_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The audience rule set: three nested tiers, plus the two sessions that see
/// everything regardless (the authoring club and the platform moderator).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<Club> originalClubs;
  late List<User> originalUsers;

  const clubId = 'audience-club';
  const otherClubId = 'audience-other-club';
  const boardMemberId = 'audience-board-member';

  NewsPost postFor(ContentAudience audience, {String club = clubId}) => NewsPost(
    id: 'audience-post-${audience.wireValue}-$club',
    clubId: club,
    authorId: 'audience-author',
    content: 'Fixture',
    createdAt: DateTime.now(),
    audience: audience,
  );

  Event eventFor(ContentAudience audience) => Event(
    id: 'audience-event-${audience.wireValue}',
    clubId: clubId,
    title: 'Fixture',
    description: 'Fixture',
    dateTime: DateTime.now().add(const Duration(days: 2)),
    endTime: DateTime.now().add(const Duration(days: 2, hours: 2)),
    location: 'Student Center',
    attendeeUserIds: const [],
    audience: audience,
  );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('content_audience_vis_');
    Hive.init(tempDir.path);
    await contentAudienceStore.initialize();
  });

  setUp(() {
    originalClubs = List<Club>.from(clubs);
    originalUsers = List<User>.from(users);
    clubs.addAll([
      Club(
        id: clubId,
        name: 'Debate Society',
        description: 'Fixture',
        adminUserIds: const [clubId],
        boardMemberIds: <String>[boardMemberId],
      ),
      Club(
        id: otherClubId,
        name: 'Robotics',
        description: 'Fixture',
        adminUserIds: const [otherClubId],
      ),
    ]);
    userState.replaceFollowedClubs(const []);
    contentAudienceStore.clearSessionState();
  });

  tearDown(() async {
    await authService.logout();
    userState.replaceFollowedClubs(const []);
    contentAudienceStore.clearSessionState();
    clubs
      ..clear()
      ..addAll(originalClubs);
    users
      ..clear()
      ..addAll(originalUsers);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String signInStudent(String slug) {
    expect(
      authService.signUp('Student $slug', '$slug@ku.edu.tr', '135790'),
      isTrue,
    );
    return authService.currentUser!.id;
  }

  test('everyone is visible to a signed-out session', () {
    expect(canViewPost(postFor(ContentAudience.everyone)), isTrue);
    expect(canViewEvent(eventFor(ContentAudience.everyone)), isTrue);
  });

  test('followers-only hides from a student who does not follow', () {
    signInStudent('nonfollower');
    expect(canViewPost(postFor(ContentAudience.followers)), isFalse);
    expect(canViewEvent(eventFor(ContentAudience.followers)), isFalse);
  });

  test('followers-only shows to a student who follows', () {
    signInStudent('follower');
    userState.replaceFollowedClubs(const [clubId]);
    expect(canViewPost(postFor(ContentAudience.followers)), isTrue);
    expect(canViewEvent(eventFor(ContentAudience.followers)), isTrue);
  });

  test('board-only hides from a plain follower', () {
    signInStudent('plainfollower');
    userState.replaceFollowedClubs(const [clubId]);
    expect(canViewPost(postFor(ContentAudience.board)), isFalse);
    expect(canViewEvent(eventFor(ContentAudience.board)), isFalse);
  });

  test('board-only shows to a board member on their personal account', () {
    signInStudent('boardmember');
    // Board membership is keyed on the club record, so put the freshly signed
    // in student on the board rather than reusing a fixture id.
    final viewerId = authService.currentUser!.id;
    final club = clubs.firstWhere((c) => c.id == clubId);
    club.boardMemberIds.add(viewerId);
    expect(canViewPost(postFor(ContentAudience.board)), isTrue);
    expect(canViewEvent(eventFor(ContentAudience.board)), isTrue);
  });

  test('the authoring club always sees its own restricted content', () {
    authService.setClubAdmin(
      AppAdmin(
        id: clubId,
        name: 'Debate Society',
        email: 'debate@ku.edu.tr',
        password: 'x',
      ),
    );
    expect(canViewPost(postFor(ContentAudience.board)), isTrue);
    expect(canViewEvent(eventFor(ContentAudience.board)), isTrue);
  });

  test('a different club does not see another club\'s board content', () {
    authService.setClubAdmin(
      AppAdmin(
        id: otherClubId,
        name: 'Robotics',
        email: 'robotics@ku.edu.tr',
        password: 'x',
      ),
    );
    expect(canViewPost(postFor(ContentAudience.board)), isFalse);
  });

  test('the platform moderator sees every tier', () {
    authService.setClubAdmin(
      AppAdmin(
        id: 'audience-platform-admin',
        name: 'ClubUp',
        email: 'ops@clubup.app',
        password: 'x',
        isPlatformAdmin: true,
      ),
    );
    expect(canViewPost(postFor(ContentAudience.board)), isTrue);
    expect(canViewEvent(eventFor(ContentAudience.board)), isTrue);
  });

  test('the board tier fails closed when boardMemberIds has not hydrated', () {
    signInStudent('unhydrated');
    final viewerId = authService.currentUser!.id;
    final club = clubs.firstWhere((c) => c.id == clubId);
    club.boardMemberIds.clear();
    userState.replaceFollowedClubs(const [clubId]);
    expect(canViewPost(postFor(ContentAudience.board)), isFalse);
    club.boardMemberIds.add(viewerId);
    expect(canViewPost(postFor(ContentAudience.board)), isTrue);
  });

  test('the local store overrides the model field', () async {
    signInStudent('override');
    final post = postFor(ContentAudience.everyone);
    expect(canViewPost(post), isTrue);
    // This is the case the whole side-store design exists for: the model was
    // rebuilt from a server row that cannot carry the column.
    await contentAudienceStore.setAudience(post.id, ContentAudience.board);
    expect(audienceForPost(post), ContentAudience.board);
    expect(canViewPost(post), isFalse);
  });
}

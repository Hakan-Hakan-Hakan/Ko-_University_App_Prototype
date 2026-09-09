import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/comment.dart';
import '../models/event.dart';
import '../models/like.dart';
import '../models/news_post.dart';
import '../models/notification.dart';
import '../models/share.dart';
import 'auth_service.dart';
import 'account_switcher_service.dart';
import 'club_admin_access.dart';
import 'guest_session.dart';
import 'mock_data.dart';
import 'mock_clubup_profile.dart';

/// Persists user-generated content (posts, events, likes, shares, and dynamic
/// notifications) to a Hive box.
class ContentStore extends ChangeNotifier {
  static const _boxName = 'content_v1';
  static const int _fixtureRemovalVersion = 1;
  static final RegExp _legacyPostId = RegExp(r'^n\d+$');
  static final RegExp _legacyEventId = RegExp(r'^ev\d+$');
  static final RegExp _legacyUserId = RegExp(r'^u\d+$');

  late Box<dynamic> _box;
  bool _initialized = false;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    // Hive.init() is already called by MessageService — just open the box.
    _box = await Hive.openBox<dynamic>(_boxName);
    _initialized = true;
  }

  /// Call after a post/event is created or edited so screens showing that
  /// content (Feed, This Week) can refresh themselves directly instead of
  /// relying on their host screen to force a rebuild.
  void notifyContentChanged() => notifyListeners();

  /// Call once after [initialize] to replace in-memory lists with stored data.
  void applyToLists() {
    // Guest mode supplies its own world; replaying the device's cached rows
    // over it would mix a real account's content into the demo.
    if (guestSession.isActive) return;
    _load(
      'comments',
      comments,
      (m) => Comment.fromMap(Map<String, dynamic>.from(m as Map)),
    );

    _load(
      'likes',
      likes,
      (m) => Like.fromMap(Map<String, dynamic>.from(m as Map)),
    );
    _load(
      'shares',
      shares,
      (m) => Share.fromMap(Map<String, dynamic>.from(m as Map)),
    );
    _load(
      'posts',
      newsPosts,
      (m) => NewsPost.fromMap(Map<String, dynamic>.from(m as Map)),
    );
    _load(
      'events',
      events,
      (m) => Event.fromMap(Map<String, dynamic>.from(m as Map)),
    );

    final storedRemovalVersion = _box.get('fixtureRemovalVersion') as int? ?? 0;
    if (storedRemovalVersion < _fixtureRemovalVersion) {
      _removeLegacyFixtures();
      unawaited(
        Future.wait([
          saveNewsPosts(),
          saveEvents(),
          saveComments(),
          saveLikes(),
          saveShares(),
          _persist('fixtureRemovalVersion', _fixtureRemovalVersion),
          _forget('seedVersion'),
        ]),
      );
    }
    unawaited(_forget('stories'));
  }

  void _removeLegacyFixtures() {
    newsPosts.removeWhere((post) => _legacyPostId.hasMatch(post.id));
    events.removeWhere((event) => _legacyEventId.hasMatch(event.id));
    comments.removeWhere(
      (comment) =>
          _legacyPostId.hasMatch(comment.postId) ||
          _legacyUserId.hasMatch(comment.userId),
    );
    likes.removeWhere(
      (like) =>
          _legacyPostId.hasMatch(like.postId) ||
          _legacyUserId.hasMatch(like.userId),
    );
    shares.removeWhere(
      (share) =>
          _legacyPostId.hasMatch(share.targetId) ||
          _legacyEventId.hasMatch(share.targetId) ||
          _legacyUserId.hasMatch(share.userId),
    );
  }

  void _load<T>(String key, List<T> target, T Function(dynamic) fromRaw) {
    final raw = _box.get(key);
    if (raw == null) return;
    target
      ..clear()
      ..addAll((raw as List).map(fromRaw));
  }

  /// Every Hive write in this store funnels through here.
  ///
  /// The guest joyride must leave nothing on disk, and it is easier to prove
  /// that with one gate than with a check on each of the nine save methods —
  /// `_initialized` is checked here too, since the box opens after first paint.
  Future<void> _persist(String key, Object? value) async {
    if (guestSession.isActive || !_initialized) return;
    await _box.put(key, value);
  }

  Future<void> _forget(String key) async {
    if (guestSession.isActive || !_initialized) return;
    await _box.delete(key);
  }

  // ── Debounced persistence ────────────────────────────────────────────────────
  // Each like/RSVP/comment/share tap used to re-serialize its ENTIRE list to
  // Hive on the main isolate (a rollback re-serialized it twice). Interaction
  // handlers call [scheduleSave] instead: dirty kinds coalesce and flush 1s
  // after the last mutation. The Supabase write still happens per-tap — only
  // this local mirror is coalesced — and app pause/detach and logout flush
  // through saveAll, so a hard crash inside the window loses at most 1s of
  // local mirror that the next launch re-derives from Supabase anyway.

  Timer? _saveDebounce;
  final Set<String> _dirtyKinds = {};

  void scheduleSave(String kind) {
    // Skip the debounce timer entirely in guest mode, so nothing is left armed
    // to fire after the joyride is torn down.
    if (guestSession.isActive) return;
    _dirtyKinds.add(kind);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), () {
      unawaited(flushPendingSaves());
    });
  }

  Future<void> flushPendingSaves() async {
    if (guestSession.isActive) return;
    _saveDebounce?.cancel();
    _saveDebounce = null;
    if (!_initialized || _dirtyKinds.isEmpty) return;
    final kinds = Set.of(_dirtyKinds);
    _dirtyKinds.clear();
    await Future.wait([
      if (kinds.contains('posts')) saveNewsPosts(),
      if (kinds.contains('events')) saveEvents(),
      if (kinds.contains('comments')) saveComments(),
      if (kinds.contains('likes')) saveLikes(),
      if (kinds.contains('shares')) saveShares(),
    ]);
  }

  // ── Save helpers ─────────────────────────────────────────────────────────────

  Future<void> saveNewsPosts() async =>
      _persist('posts', newsPosts.map((p) => p.toMap()).toList());

  Future<void> saveEvents() async =>
      _persist('events', events.map((e) => e.toMap()).toList());

  Future<void> saveComments() async =>
      _persist('comments', comments.map((c) => c.toMap()).toList());

  Future<void> saveLikes() async =>
      _persist('likes', likes.map((l) => l.toMap()).toList());

  Future<void> saveShares() async =>
      _persist('shares', shares.map((s) => s.toMap()).toList());

  Future<void> saveDynamicNotifications(List<AppNotification> ns) async =>
      _persist(
        'dynNotifs',
        ns.where((n) => n.targetType != 'story').map((n) => n.toMap()).toList(),
      );

  Future<void> saveReadNotificationIds(Set<String> ids) async =>
      _persist('readNotifIds', ids.toList());

  Set<String> loadReadNotificationIds() {
    final raw = _box.get('readNotifIds');
    if (raw is! List) return <String>{};
    return raw.map((id) => id.toString()).toSet();
  }

  List<AppNotification>? loadDynamicNotifications() {
    final raw = _box.get('dynNotifs');
    if (raw == null) return null;
    return (raw as List)
        .map(
          (m) => AppNotification.fromMap(Map<String, dynamic>.from(m as Map)),
        )
        .where(
          (notification) =>
              notification.targetType != 'story' &&
              !_legacyUserId.hasMatch(notification.userId) &&
              !_legacyPostId.hasMatch(notification.targetId ?? '') &&
              !_legacyEventId.hasMatch(notification.targetId ?? ''),
        )
        .toList();
  }

  // ── Club board member IDs ────────────────────────────────────────────────────
  // Only the mutable boardMemberIds list is persisted here; club records are
  // hydrated from Supabase.

  Future<void> saveBoardMemberIds() async {
    final map = <String, List<String>>{};
    for (final club in clubs) {
      map[club.id] = List<String>.from(club.boardMemberIds);
    }
    await _persist('boardMemberIds', map);
  }

  void loadBoardMemberIds() {
    final raw = _box.get('boardMemberIds');
    if (raw == null) return;
    final map = Map<String, dynamic>.from(raw as Map);
    for (final club in clubs) {
      final stored = map[club.id];
      if (stored != null) {
        club.boardMemberIds
          ..clear()
          ..addAll(List<String>.from(stored as List));
      }
    }
  }

  // ── Club board member titles ─────────────────────────────────────────────────

  Future<void> saveBoardMemberTitles() async {
    // Hive cannot serialise nested typed maps — store as Map<String, dynamic>
    // where each value is itself a Map<String, dynamic> (userId → title).
    final outer = <String, dynamic>{};
    for (final club in clubs) {
      outer[club.id] = Map<String, dynamic>.from(club.boardMemberTitles);
    }
    await _persist('boardMemberTitles', outer);
  }

  void loadBoardMemberTitles() {
    final raw = _box.get('boardMemberTitles');
    if (raw == null) return;
    final outer = Map<String, dynamic>.from(raw as Map);
    for (final club in clubs) {
      final stored = outer[club.id];
      if (stored == null) continue;
      final inner = Map<String, dynamic>.from(stored as Map);
      club.boardMemberTitles
        ..clear()
        ..addAll(inner.map((k, v) => MapEntry(k, v as String)));
    }
  }

  // ── Club-admin deletion ───────────────────────────────────────────────────────
  // Club admins can delete only their club's content. The verified platform
  // administrator can delete any post or event.

  bool _isClubAdmin(String clubId, String userId) {
    if (clubs.any((c) => c.id == clubId && clubIsManagedByAdmin(c, userId))) {
      return true;
    }

    // In production a dedicated club login has two IDs: the Supabase auth UUID
    // used as actorId and the club UUID stored in authService.currentAdmin. If
    // this is the real signed-in actor, authorize against the account currently
    // represented by the UI instead of comparing the auth UUID to the club ID.
    return accountSwitcherService.actorId == userId &&
        currentAccountManagesClubId(clubId);
  }

  bool _isPlatformAdmin(String userId) {
    final admin = authService.currentAdmin;
    return userId.isNotEmpty && admin?.id == userId && isClubUpAdmin(admin);
  }

  bool canDeleteEvent(String eventId, String requestingUserId) {
    return events.any(
      (e) =>
          e.id == eventId &&
          (_isPlatformAdmin(requestingUserId) ||
              _isClubAdmin(e.clubId, requestingUserId)),
    );
  }

  bool canDeletePost(String postId, String requestingUserId) {
    return newsPosts.any(
      (p) =>
          p.id == postId &&
          (_isPlatformAdmin(requestingUserId) ||
              _isClubAdmin(p.clubId, requestingUserId)),
    );
  }

  bool canEditEvent(String eventId, String requestingUserId) {
    return events.any(
      (event) =>
          event.id == eventId && _isClubAdmin(event.clubId, requestingUserId),
    );
  }

  /// Replaces the stored event with [updated] (matched by id) when the
  /// requester is a club admin of that event's club. Returns false otherwise.
  bool updateEvent(Event updated, String requestingUserId) {
    final idx = events.indexWhere((e) => e.id == updated.id);
    if (idx == -1) return false;
    if (!_isClubAdmin(updated.clubId, requestingUserId)) return false;
    events[idx] = updated;
    unawaited(saveEvents());
    notifyContentChanged();
    return true;
  }

  /// Replaces an event after checking the account currently represented by
  /// the UI. This avoids mixing the Supabase auth UUID with the club UUID used
  /// by dedicated club-admin sessions.
  bool updateEventForCurrentAccount(Event updated) {
    final idx = events.indexWhere((event) => event.id == updated.id);
    if (idx == -1 || !currentAccountManagesClubId(updated.clubId)) {
      return false;
    }
    events[idx] = updated;
    if (_initialized) unawaited(saveEvents());
    notifyContentChanged();
    return true;
  }

  bool deleteEvent(String eventId, String requestingUserId) {
    final idx = events.indexWhere((e) => e.id == eventId);
    if (idx == -1) return false;
    if (!canDeleteEvent(eventId, requestingUserId)) return false;
    events.removeAt(idx);
    unawaited(saveEvents());
    notifyContentChanged();
    return true;
  }

  bool deletePost(String postId, String requestingUserId) {
    final idx = newsPosts.indexWhere((p) => p.id == postId);
    if (idx == -1) return false;
    if (!canDeletePost(postId, requestingUserId)) return false;
    newsPosts.removeAt(idx);
    saveNewsPosts();
    notifyContentChanged();
    return true;
  }

  // ── Save everything at once ───────────────────────────────────────────────────

  Future<void> saveAll(List<AppNotification> dynamicNotifs) async {
    // Everything below rewrites the debounced kinds anyway.
    if (guestSession.isActive) return;
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _dirtyKinds.clear();
    // Boxes open in the background after first paint; a lifecycle pause on
    // the login screen can land here before they're ready.
    if (!_initialized) return;
    await Future.wait([
      saveNewsPosts(),
      saveEvents(),
      saveComments(),
      saveLikes(),
      saveShares(),
      saveDynamicNotifications(dynamicNotifs),
      saveBoardMemberIds(),
      saveBoardMemberTitles(),
    ]);
  }
}

final contentStore = ContentStore();

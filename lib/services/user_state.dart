import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/notification.dart';
import 'content_store.dart';
import 'locale_service.dart';
import 'photo_file_cache.dart';

// Global state singleton. Extends ChangeNotifier so any ListenableBuilder
// that wraps a follow button will rebuild instantly when state changes,
// regardless of which screen triggered the mutation.
class UserState extends ChangeNotifier {
  // No BuildContext is available this deep in the service layer; these
  // generated in-app notification messages are resolved here via the
  // current locale.
  AppLocalizations get _l10n =>
      lookupAppLocalizations(Locale(localeService.languageCode));
  final Set<String> likedPostIds = {};
  final Set<String> followedClubIds = {};
  final Set<String> savedPostIds = {};
  final Set<String> followedUserIds = {};
  bool _followedClubsLoading = false;

  bool get followedClubsLoading => _followedClubsLoading;

  void setFollowedClubsLoading(bool loading) {
    if (_followedClubsLoading == loading) return;
    _followedClubsLoading = loading;
    notifyListeners();
  }

  @Deprecated('Use unreadNotificationCountFor instead.')
  int unreadNotifications = 0;

  // Profile photo image paths keyed by user/admin id.
  final Map<String, String> profilePhotoPaths = {};

  // The local avatar filename is intentionally stable. Incrementing this
  // token lets selective listeners distinguish new bytes written to the same
  // path, even when a remote upload is unavailable.
  final Map<String, int> _profilePhotoRevisions = {};

  int profilePhotoRevisionFor(String userId) =>
      _profilePhotoRevisions[userId] ?? 0;

  void _bumpProfilePhotoRevision(String userId) {
    _profilePhotoRevisions[userId] = profilePhotoRevisionFor(userId) + 1;
  }

  /// Remote profile photo URLs hydrated from Supabase.
  final Map<String, String> remotePhotoUrls = {};

  // Student bios keyed by user id.
  final Map<String, String> bios = {};

  // Student majors keyed by user id.
  final Map<String, String> majors = {};

  // Student years keyed by user id.
  final Map<String, String> years = {};

  /// A compact label for messaging and directory rows. Missing profile
  /// fields are omitted so the UI never shows empty separators.
  String academicSummaryFor(String userId) {
    final major = majors[userId]?.trim() ?? '';
    final year = years[userId]?.trim() ?? '';
    return [major, year].where((value) => value.isNotEmpty).join(' · ');
  }

  // Student interest topics keyed by user id.
  final Map<String, List<String>> interests = {};

  // Student minor program(s) keyed by user id.
  final Map<String, List<String>> minors = {};

  // Student double-major program(s) keyed by user id.
  final Map<String, List<String>> doubleMajors = {};

  // Club profile photo paths keyed by club id.
  final Map<String, String> clubPhotoPaths = {};

  /// Remote club photo URLs hydrated from Supabase.
  final Map<String, String> remoteClubPhotoUrls = {};

  /// Notifies listeners after a club's editable info (e.g. description) changed
  /// in place, so every screen showing the club rebuilds.
  void bumpClubInfo() => notifyListeners();

  /// Sets the club photo path for [clubId] and notifies all listeners.
  void setClubPhoto(String clubId, String path) {
    // Club photos are overwritten at a stable path. Remove the old decoded
    // bitmap (in-memory) and, for a network URL, the disk-cached bytes too —
    // otherwise CachedNetworkImage would keep serving the old photo from
    // disk indefinitely, even across app restarts.
    PaintingBinding.instance.imageCache.evict(_imageProviderFor(path));
    if (_isNetworkPath(path)) {
      unawaited(CachedNetworkImage.evictFromCache(path));
    }
    photoFileCache.invalidate(clubPhotoPaths[clubId]);
    photoFileCache.invalidate(path);
    clubPhotoPaths[clubId] = path;
    notifyListeners();
  }

  void removeClubPhoto(String clubId) {
    final removed = clubPhotoPaths.remove(clubId);
    photoFileCache.invalidate(removed);
    if (removed != null) notifyListeners();
  }

  /// Sets the profile photo path for [userId] and notifies all listeners.
  void setProfilePhoto(String userId, String path) {
    PaintingBinding.instance.imageCache.evict(_imageProviderFor(path));
    if (_isNetworkPath(path)) {
      unawaited(CachedNetworkImage.evictFromCache(path));
    }
    photoFileCache.invalidate(profilePhotoPaths[userId]);
    photoFileCache.invalidate(path);
    profilePhotoPaths[userId] = path;
    _bumpProfilePhotoRevision(userId);
    notifyListeners();
  }

  bool _isNetworkPath(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  ImageProvider _imageProviderFor(String path) {
    if (_isNetworkPath(path)) {
      return NetworkImage(path);
    }
    return FileImage(File(path));
  }

  void _evictNetworkPhoto(String url) {
    PaintingBinding.instance.imageCache.evict(NetworkImage(url));
    PaintingBinding.instance.imageCache.evict(CachedNetworkImageProvider(url));
    unawaited(CachedNetworkImage.evictFromCache(url));
  }

  /// Removes the profile photo for [userId] and notifies all listeners.
  void removeProfilePhoto(String userId) {
    final removedLocal = profilePhotoPaths.remove(userId);
    photoFileCache.invalidate(removedLocal);
    final removedRemote = remotePhotoUrls.remove(userId) != null;
    if (removedLocal != null || removedRemote) {
      _bumpProfilePhotoRevision(userId);
      notifyListeners();
    }
  }

  /// Sets a remote profile photo URL for [userId] and notifies all listeners.
  void setProfilePhotoUrl(
    String userId,
    String url, {
    bool preserveLocal = false,
  }) {
    final value = url.trim();
    final previousRemote = remotePhotoUrls[userId];
    final localPath = preserveLocal ? null : profilePhotoPaths.remove(userId);
    if (!preserveLocal && localPath != null) {
      PaintingBinding.instance.imageCache.evict(FileImage(File(localPath)));
      photoFileCache.invalidate(localPath);
    }

    // Profile hydration runs from several surfaces (chat participants,
    // followers, feed items). Re-applying the same URL must not evict the
    // cached bytes or bump the revision, otherwise every surface makes its
    // avatars appear to reload when it is opened.
    if (previousRemote == value) {
      if (localPath != null) notifyListeners();
      return;
    }

    if (previousRemote != null) {
      _evictNetworkPhoto(previousRemote);
    }
    if (value.isEmpty) {
      remotePhotoUrls.remove(userId);
    } else {
      remotePhotoUrls[userId] = value;
    }
    _bumpProfilePhotoRevision(userId);
    notifyListeners();
  }

  bool hasProfilePhoto(String userId) =>
      profilePhotoPaths[userId] != null || remotePhotoUrls[userId] != null;

  /// Sets the student bio for [userId] and notifies all listeners.
  void setBio(String userId, String bio) {
    final value = bio.trim();
    if (value.isEmpty) {
      bios.remove(userId);
    } else {
      bios[userId] = value;
    }
    notifyListeners();
  }

  /// Sets the student major for [userId] and notifies all listeners.
  void setMajor(String userId, String major) {
    final value = major.trim();
    if (value.isEmpty) {
      majors.remove(userId);
    } else {
      majors[userId] = value;
    }
    notifyListeners();
  }

  /// Sets the student year for [userId] and notifies all listeners.
  void setYear(String userId, String year) {
    final value = year.trim();
    if (value.isEmpty) {
      years.remove(userId);
    } else {
      years[userId] = value;
    }
    notifyListeners();
  }

  /// Sets the student interest topics for [userId] and notifies all listeners.
  void setInterests(String userId, List<String> topics) {
    final values = topics.map((topic) => topic.trim()).where((topic) {
      return topic.isNotEmpty;
    }).toList();
    if (values.isEmpty) {
      interests.remove(userId);
    } else {
      interests[userId] = values;
    }
    notifyListeners();
  }

  /// Sets the student's minor program for [userId] and notifies all listeners.
  void setMinors(String userId, List<String> values) {
    final v = values
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(1)
        .toList();
    if (v.isEmpty) {
      minors.remove(userId);
    } else {
      minors[userId] = v;
    }
    notifyListeners();
  }

  /// Sets the student's double-major program for [userId] and notifies listeners.
  void setDoubleMajors(String userId, List<String> values) {
    final v = values
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(1)
        .toList();
    if (v.isEmpty) {
      doubleMajors.remove(userId);
    } else {
      doubleMajors[userId] = v;
    }
    notifyListeners();
  }

  // ── Usernames ─────────────────────────────────────────────────────────────────

  /// Custom usernames keyed by user/admin id. If absent the real name is used.
  final Map<String, String> usernames = {};

  /// Returns the custom username for [userId] if set, otherwise null.
  String? usernameFor(String userId) => usernames[userId];

  /// Sets [username] for [userId] and notifies listeners.
  void setUsername(String userId, String username) {
    usernames[userId] = username;
    notifyListeners();
  }

  /// Removes the custom username for [userId] (reverts to real name).
  void clearUsername(String userId) {
    usernames.remove(userId);
    notifyListeners();
  }

  /// Returns true if [username] is already taken by someone other than [excludeId].
  bool isUsernameTaken(String username, {String? excludeId}) {
    final lower = username.toLowerCase();
    return usernames.entries.any(
      (e) => e.key != excludeId && e.value.toLowerCase() == lower,
    );
  }

  /// The display name to show publicly for [userId]: username if set, else [fallbackName].
  String displayNameFor(String userId, String fallbackName) =>
      usernames[userId] ?? fallbackName;

  // ── Follow requests ───────────────────────────────────────────────────────────

  /// IDs I have sent a pending follow request to (not yet accepted).
  final Set<String> pendingFollowRequests = {};

  /// IDs where I have already seen the "they don't follow you back" notice,
  /// so we don't show it again on subsequent follows.
  final Set<String> shownFollowNotice = {};

  /// Incoming follow requests waiting for MY decision.
  /// Key = fromId (who sent me the request), Value = notification id.
  final Map<String, String> incomingFollowRequests = {};

  bool hasPendingRequest(String userId) =>
      pendingFollowRequests.contains(userId);

  /// Called when user [fromId] sends a follow request to [toId].
  /// Adds a follow_request notification to the target's alerts.
  void sendFollowRequest(String fromId, String toId, String fromName) {
    pendingFollowRequests.add(toId);
    final notifId =
        'follow_req_${fromId}_${DateTime.now().millisecondsSinceEpoch}';
    incomingFollowRequests[fromId] = notifId;
    final notif = AppNotification(
      id: notifId,
      userId: toId,
      message: _l10n.followRequestMessage(fromName),
      createdAt: DateTime.now(),
      targetType: 'follow_request',
      targetId: fromId,
      fromId: fromId,
    );
    addFollowRequestNotification(notif);
    notifyListeners();
  }

  /// Accept an incoming follow request from [fromId].
  void acceptFollowRequest(String fromId, String toId) {
    pendingFollowRequests.remove(toId);
    incomingFollowRequests.remove(fromId);
    followedUserIds.add(toId);
    acceptedMessageRequests.add('$fromId:$toId');
    // Notify the requester that their request was accepted.
    final notif = AppNotification(
      id: 'follow_accepted_${fromId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: fromId,
      message: _l10n.followRequestAccepted,
      createdAt: DateTime.now(),
      targetType: 'follow_accepted',
      targetId: toId,
    );
    addNotification(notif);
    notifyListeners();
  }

  /// Decline an incoming follow request from [fromId].
  void declineFollowRequest(String fromId) {
    pendingFollowRequests.remove(fromId);
    incomingFollowRequests.remove(fromId);
    notifyListeners();
  }

  // ── Notification helpers ──────────────────────────────────────────────────────

  /// Adds a follow-request notification WITHOUT firing the in-app banner
  /// (it already shows as a card in the alerts tab).
  void addFollowRequestNotification(AppNotification n) {
    addNotification(n);
  }

  // ── Message requests ──────────────────────────────────────────────────────────

  /// Accepted message request pairs stored as "myId:theirId".
  final Set<String> acceptedMessageRequests = {};

  bool hasAcceptedMessageRequest(String myId, String theirId) =>
      acceptedMessageRequests.contains('$myId:$theirId');

  void acceptMessageRequest(String myId, String theirId) =>
      acceptedMessageRequests.add('$myId:$theirId');

  // ── Notifications ─────────────────────────────────────────────────────────────

  /// Dynamic notifications generated at runtime (likes, follows, mentions…).
  final List<AppNotification> dynamicNotifications = [];
  final Set<String> readNotificationIds = {};

  void addNotification(AppNotification n) {
    if (n.targetType == 'story') return;
    if (dynamicNotifications.any((existing) => existing.id == n.id)) return;

    final conversationKey = notificationConversationKey(n);
    if (conversationKey != null) {
      final existingIndex = dynamicNotifications.indexWhere(
        (existing) => notificationConversationKey(existing) == conversationKey,
      );
      if (existingIndex >= 0) {
        final previous = dynamicNotifications[existingIndex];
        readNotificationIds.remove(previous.id);
        dynamicNotifications[existingIndex] = n;
        unreadNotifications = unreadNotificationCountFor(dynamicNotifications);
        contentStore.saveDynamicNotifications(dynamicNotifications);
        notifyListeners();
        return;
      }
    }

    dynamicNotifications.insert(0, n);
    unreadNotifications = unreadNotificationCountFor(dynamicNotifications);
    contentStore.saveDynamicNotifications(dynamicNotifications);
    notifyListeners();
  }

  void replaceReadNotificationIds(Iterable<String> ids) {
    readNotificationIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  bool isNotificationRead(AppNotification n) =>
      n.read || readNotificationIds.contains(n.id);

  int unreadNotificationCountFor(Iterable<AppNotification> source) {
    return source.where((n) {
      return n.targetType != 'story' && !isNotificationRead(n);
    }).length;
  }

  void markNotificationRead(AppNotification n) {
    if (readNotificationIds.add(n.id)) {
      unreadNotifications = unreadNotificationCountFor(dynamicNotifications);
      contentStore.saveReadNotificationIds(readNotificationIds);
      notifyListeners();
    }
  }

  void markNotificationsRead(Iterable<AppNotification> source) {
    var changed = false;
    for (final n in source) {
      if (n.targetType == 'story') continue;
      changed = readNotificationIds.add(n.id) || changed;
    }
    if (changed) {
      unreadNotifications = unreadNotificationCountFor(dynamicNotifications);
      contentStore.saveReadNotificationIds(readNotificationIds);
      notifyListeners();
    }
  }

  /// Marks locally cached alerts for exactly one open chat as read.
  void markChatThreadNotificationsRead({
    required String threadId,
    required String userId,
  }) {
    final conversationKey = notificationConversationKeyForThread(
      threadId: threadId,
      userId: userId,
    );
    if (conversationKey == null) return;
    markNotificationsRead(
      dynamicNotifications.where(
        (notification) =>
            notificationConversationKey(notification) == conversationKey,
      ),
    );
  }

  // ── Pinned club posts (global; set by a club's admin) ───────────────────────
  final Set<String> pinnedPostIds = {};

  bool isPostPinned(String postId) => pinnedPostIds.contains(postId);

  void togglePinnedPost(String postId) {
    if (!pinnedPostIds.remove(postId)) pinnedPostIds.add(postId);
    notifyListeners();
  }

  // ── Likes / saves ─────────────────────────────────────────────────────────────

  bool isLiked(String postId) => likedPostIds.contains(postId);

  void replaceLikedPosts(Iterable<String> postIds) {
    likedPostIds
      ..clear()
      ..addAll(postIds);
    notifyListeners();
  }

  /// Merges per-card viewer state returned by Feed v2 without replacing like
  /// state for posts loaded by another surface.
  void seedFeedLikeStates(Map<String, bool> states) {
    var changed = false;
    for (final entry in states.entries) {
      if (entry.value) {
        changed = likedPostIds.add(entry.key) || changed;
      } else {
        changed = likedPostIds.remove(entry.key) || changed;
      }
    }
    if (changed) notifyListeners();
  }

  void toggleLike(String postId) {
    if (likedPostIds.contains(postId)) {
      likedPostIds.remove(postId);
    } else {
      likedPostIds.add(postId);
    }
    notifyListeners();
  }

  bool isFollowing(String clubId) => followedClubIds.contains(clubId);

  String? get activeClubId =>
      followedClubIds.isEmpty ? null : followedClubIds.first;

  void replaceFollowedClubs(Iterable<String> clubIds) {
    followedClubIds
      ..clear()
      ..addAll(clubIds);
    notifyListeners();
  }

  void joinClub(String clubId, {bool exclusive = false}) {
    if (exclusive) followedClubIds.clear();
    followedClubIds.add(clubId);
    notifyListeners();
  }

  void leaveClub(String clubId) {
    followedClubIds.remove(clubId);
    notifyListeners();
  }

  void toggleFollow(String clubId) {
    if (followedClubIds.contains(clubId)) {
      followedClubIds.remove(clubId);
    } else {
      followedClubIds.add(clubId);
    }
    notifyListeners();
  }

  bool isSaved(String postId) => savedPostIds.contains(postId);

  void toggleSave(String postId) {
    if (savedPostIds.contains(postId)) {
      savedPostIds.remove(postId);
    } else {
      savedPostIds.add(postId);
    }
    notifyListeners();
  }

  bool isFollowingUser(String userId) => followedUserIds.contains(userId);

  void replaceFollowedUsers(Iterable<String> userIds) {
    followedUserIds
      ..clear()
      ..addAll(userIds);
    notifyListeners();
  }

  void setFollowingUser(String userId, bool follow) {
    if (follow) {
      followedUserIds.add(userId);
    } else {
      followedUserIds.remove(userId);
      pendingFollowRequests.remove(userId);
    }
    notifyListeners();
  }

  void toggleFollowUser(String userId) {
    if (followedUserIds.contains(userId)) {
      followedUserIds.remove(userId);
      pendingFollowRequests.remove(userId);
    } else {
      followedUserIds.add(userId);
    }
    notifyListeners();
  }

  // ── Session boundary ──────────────────────────────────────────────────────────

  /// Drops every piece of per-account state this singleton holds.
  ///
  /// [userState] outlives any one account, so entering or leaving the guest
  /// joyride has to empty it explicitly — otherwise the previous occupant's
  /// likes, follows, bios and alerts bleed into the demo (and the demo's bleed
  /// back out). Deliberately notifies once at the end rather than per field.
  void resetForSessionBoundary() {
    likedPostIds.clear();
    followedClubIds.clear();
    savedPostIds.clear();
    followedUserIds.clear();
    pinnedPostIds.clear();
    profilePhotoPaths.clear();
    remotePhotoUrls.clear();
    _profilePhotoRevisions.clear();
    clubPhotoPaths.clear();
    remoteClubPhotoUrls.clear();
    bios.clear();
    majors.clear();
    years.clear();
    interests.clear();
    minors.clear();
    doubleMajors.clear();
    usernames.clear();
    pendingFollowRequests.clear();
    shownFollowNotice.clear();
    incomingFollowRequests.clear();
    acceptedMessageRequests.clear();
    dynamicNotifications.clear();
    readNotificationIds.clear();
    unreadNotifications = 0;
    _followedClubsLoading = false;
    notifyListeners();
  }

  // This is a process-lifetime singleton shared by ~20+ plain
  // ListenableBuilder(listenable: userState) call sites app-wide, in
  // addition to userStateProvider below. Riverpod's ChangeNotifierProvider
  // calls dispose() on the notifier it's given whenever its own scope tears
  // down (e.g. a fresh ProviderScope per widget test) — since that scope
  // doesn't own this singleton, disposing it would permanently break every
  // other consumer. Overriding dispose() to a no-op keeps it alive for the
  // whole process, matching every other singleton service in this codebase.
  @override
  // ignore: must_call_super
  void dispose() {}
}

final userState = UserState();

/// Bridges the existing [userState] singleton into Riverpod so widgets can
/// `.select()` a single field instead of rebuilding on every mutation via a
/// whole-object [ListenableBuilder].
final userStateProvider = ChangeNotifierProvider<UserState>((ref) => userState);

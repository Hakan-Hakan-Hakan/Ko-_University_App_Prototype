import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';
import 'locale_service.dart';
import 'supabase_config.dart';
import 'guest_session.dart';

String? notificationGroupKeyFromPushData(Map<String, dynamic> data) {
  final explicit = data['notification_group_key']?.toString().trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;

  String normalize(String value) =>
      value.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

  final type = data['type']?.toString().trim();
  final normalizedType = type == null || type.isEmpty ? '' : normalize(type);
  final targetType = data['target_type']?.toString().trim().toLowerCase();
  final targetId = data['target_id']?.toString().trim();
  if (targetId == null || targetId.isEmpty || targetType != 'message') {
    return null;
  }

  if (normalizedType == 'direct_message' || targetId.startsWith('dm:')) {
    final peer = data['actor_user_id']?.toString().trim();
    return 'direct:${peer == null || peer.isEmpty ? targetId : peer}';
  }
  if (normalizedType == 'group_message' || targetId.startsWith('group:')) {
    return 'group:${targetId.replaceFirst('group:', '')}';
  }
  if (normalizedType == 'club_channel_message' ||
      targetId.startsWith('club:')) {
    return 'club:${targetId.replaceFirst('club:', '')}';
  }
  if (normalizedType == 'club_inbox_message' ||
      targetId.startsWith('clubdm:')) {
    return 'club_inbox:${targetId.replaceFirst('clubdm:', '')}';
  }
  return 'message:${normalizedType.isEmpty ? 'unknown' : normalizedType}:$targetId';
}

/// Pushes created by the current delivery pipeline name their recipient.
/// Legacy chat pushes without that binding fail closed because their content
/// cannot be proven to belong to the signed-in account.
bool pushDataBelongsToUser(
  Map<String, dynamic> data, {
  required String currentUserId,
}) {
  final recipientId = data['recipient_user_id']?.toString().trim();
  if (recipientId != null && recipientId.isNotEmpty) {
    return currentUserId.isNotEmpty && recipientId == currentUserId;
  }

  final type = data['type']
      ?.toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  final targetType = data['target_type']?.toString().trim().toLowerCase();
  final isUnboundChatPush =
      targetType == 'message' ||
      targetType == 'chat' ||
      const {
        'direct_message',
        'group_message',
        'club_channel_message',
        'club_inbox_message',
      }.contains(type);
  return !isUnboundChatPush;
}

class PushNotificationTarget {
  const PushNotificationTarget({
    required this.type,
    this.targetId,
    this.notificationId,
    this.notificationType,
    this.actorId,
  });

  /// The normalized navigation destination. Messaging destinations retain
  /// their subtype (`direct_message`, `group_chat`, or `club_chat`) because
  /// each one needs a different thread-id shape.
  final String type;
  final String? targetId;
  final String? notificationId;
  final String? notificationType;
  final String? actorId;

  bool get isChat => const {
    'direct_message',
    'group_chat',
    'club_chat',
    'club_inbox',
  }.contains(type);

  /// Builds the canonical thread id expected by [ChatThreadScreen]. Backend
  /// notification rows store raw peer/group/club UUIDs, while the messaging
  /// system uses prefixed ids locally.
  String? chatThreadIdFor(String currentUserId) {
    final id = targetId;
    if (!isChat || id == null || id.isEmpty) return null;
    if (id.startsWith('dm:') ||
        id.startsWith('group:') ||
        id.startsWith('club:') ||
        id.startsWith('clubdm:')) {
      return id;
    }
    switch (type) {
      case 'group_chat':
        return 'group:$id';
      case 'club_chat':
        return 'club:$id';
      case 'club_inbox':
        return 'clubdm:$id';
      case 'direct_message':
        final peerId = actorId ?? id;
        if (currentUserId.isEmpty ||
            peerId.isEmpty ||
            peerId == currentUserId) {
          return null;
        }
        final participants = [currentUserId, peerId]..sort();
        return 'dm:${participants.join('|')}';
    }
    return null;
  }

  factory PushNotificationTarget.fromData(Map<String, dynamic> data) {
    String? value(String key) {
      final text = data[key]?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    String normalize(String value) =>
        value.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    final notificationType = value('type') ?? value('notification_type');
    final rawTargetType = value('target_type') ?? value('targetType');
    final targetId =
        value('target_id') ??
        value('targetId') ??
        value('thread_id') ??
        value('chat_id');
    final normalizedNotificationType = notificationType == null
        ? null
        : normalize(notificationType);
    final normalizedTargetType = rawTargetType == null
        ? null
        : normalize(rawTargetType);

    String messagingType() {
      if (normalizedNotificationType == 'club_channel_message') {
        return 'club_chat';
      }
      if (normalizedNotificationType == 'club_inbox_message') {
        return 'club_inbox';
      }
      if (normalizedNotificationType == 'direct_message' ||
          normalizedTargetType == 'direct_message' ||
          normalizedTargetType == 'dm') {
        return 'direct_message';
      }
      if (normalizedNotificationType == 'group_message' ||
          normalizedTargetType == 'group_message' ||
          normalizedTargetType == 'group_chat' ||
          normalizedTargetType == 'group') {
        return 'group_chat';
      }
      if (normalizedTargetType == 'club_message' ||
          normalizedTargetType == 'club_chat' ||
          normalizedTargetType == 'community') {
        return 'club_chat';
      }
      if (targetId?.startsWith('group:') == true) return 'group_chat';
      if (targetId?.startsWith('club:') == true) return 'club_chat';
      if (targetId?.startsWith('clubdm:') == true) return 'club_inbox';
      return 'direct_message';
    }

    String navigationType() {
      final targetType = normalizedTargetType;
      if (targetType == 'message' || targetType == 'chat') {
        return messagingType();
      }
      if (targetType != null) {
        switch (targetType) {
          case 'dm':
          case 'direct_message':
          case 'group':
          case 'group_chat':
          case 'group_message':
          case 'club_chat':
          case 'club_message':
          case 'community':
          case 'club_inbox':
            return messagingType();
          case 'profile':
          case 'person':
          case 'follow_accepted':
            return 'user';
          default:
            return targetType;
        }
      }

      switch (normalizedNotificationType) {
        case 'dm':
        case 'direct_message':
          return 'direct_message';
        case 'group':
        case 'group_chat':
        case 'group_message':
          return 'group_chat';
        case 'club_chat':
        case 'club_message':
        case 'community':
          return 'club_chat';
        case 'club_inbox':
        case 'club_inbox_message':
          return 'club_inbox';
        case 'club_post':
        case 'post_like':
        case 'post_comment':
          return 'post';
        case 'club_event':
        case 'event_rsvp':
          return 'event';
        case 'profile_follow':
        case 'follow_accepted':
          return 'user';
        case 'message':
        case 'chat':
          return messagingType();
        case final type?:
          return type;
        default:
          return 'notification';
      }
    }

    return PushNotificationTarget(
      type: navigationType(),
      targetId: targetId,
      notificationId: value('notification_id') ?? value('notificationId'),
      notificationType: notificationType,
      actorId: value('actor_user_id') ?? value('from_id') ?? value('sender_id'),
    );
  }
}

class PushNotificationService extends ChangeNotifier {
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool _initialized = false;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<Map<String, dynamic>>? _localTapSubscription;
  PushNotificationTarget? _pendingTarget;

  PushNotificationTarget? takePendingTarget() {
    final target = _pendingTarget;
    _pendingTarget = null;
    return target;
  }

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    _initialized = true;

    await notificationService.initialize();
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(_upsertToken(token)),
    );
    _localTapSubscription = notificationService.remoteNotificationTaps.listen(
      _queueTarget,
    );
    localeService.addListener(_handleLocaleChanged);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleOpenedMessage(initialMessage);
  }

  Future<void> activateForCurrentUser() async {
    if (!isSupported || !SupabaseConfig.isConfigured) return;
    await initialize();

    // A guest has no account to deliver a push to, and must never see the OS
    // notification-permission prompt. (There is also no Supabase auth user in
    // a guest session, so the check below would catch it too.)
    if (guestSession.isActive) return;

    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final hasApnsToken = await _waitForApnsToken();
      if (!hasApnsToken) return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    if (kDebugMode) debugPrint('ClubUp FCM token: $token');
    await _upsertToken(token);
  }

  Future<bool> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      if (await FirebaseMessaging.instance.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<void> _upsertToken(String token) async {
    if (!SupabaseConfig.isConfigured) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      await client.from('push_devices').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'notifications_enabled': true,
        'locale': localeService.languageCode == 'tr' ? 'tr' : 'en',
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Could not register this device for push: $error');
      }
    }
  }

  void _handleLocaleChanged() => unawaited(_refreshCurrentTokenLocale());

  Future<void> _refreshCurrentTokenLocale() async {
    if (!isSupported || !SupabaseConfig.isConfigured) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _upsertToken(token);
  }

  Future<void> unregisterCurrentDevice() async {
    if (!isSupported || !SupabaseConfig.isConfigured || !_initialized) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await client
          .from('push_devices')
          .delete()
          .eq('user_id', user.id)
          .eq('fcm_token', token);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Could not unregister this device from push: $error');
      }
    }
  }

  /// Ends push delivery for the account that is about to sign out and removes
  /// already-delivered alerts so the next person using this device cannot see
  /// the previous account's notification content.
  Future<void> deactivateCurrentUser() async {
    _pendingTarget = null;
    // Logging out is valid before the post-frame Firebase bootstrap completes.
    // Do not turn a cleanup call into the first Firebase API access.
    if (!isSupported || !_initialized) return;
    await unregisterCurrentDevice();
    await notificationService.cancelAllNotifications();
  }

  bool _isForSignedInUser(Map<String, dynamic> data) {
    if (!SupabaseConfig.isConfigured) return false;
    try {
      return pushDataBelongsToUser(
        data,
        currentUserId: Supabase.instance.client.auth.currentUser?.id ?? '',
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!_isForSignedInUser(message.data)) return;
    final remoteNotification = message.notification;
    final title =
        remoteNotification?.title ?? message.data['title']?.toString();
    final body = remoteNotification?.body ?? message.data['body']?.toString();
    if (title == null || body == null) return;

    // FCM's notification payload is rendered by the OS in the background,
    // while foreground messages need a local notification. Reusing this key
    // keeps both paths on the same per-chat notification slot.
    final groupKey = notificationGroupKeyFromPushData(message.data);
    final notificationKey =
        groupKey ??
        'notification:${message.data['notification_id'] ?? message.messageId ?? '$title:$body'}';
    await notificationService.showRemoteNotification(
      id: notificationService.notificationIdFor(notificationKey),
      title: title,
      body: body,
      data: message.data,
      groupKey: groupKey,
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (_isForSignedInUser(message.data)) _queueTarget(message.data);
  }

  void _queueTarget(Map<String, dynamic> data) {
    if (!_isForSignedInUser(data)) return;
    _pendingTarget = PushNotificationTarget.fromData(data);
    notifyListeners();
  }

  @override
  void dispose() {
    localeService.removeListener(_handleLocaleChanged);
    unawaited(_foregroundSubscription?.cancel());
    unawaited(_openedSubscription?.cancel());
    unawaited(_tokenSubscription?.cancel());
    unawaited(_localTapSubscription?.cancel());
    super.dispose();
  }
}

final pushNotificationService = PushNotificationService();

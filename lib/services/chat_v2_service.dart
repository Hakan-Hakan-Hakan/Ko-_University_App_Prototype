import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/chat_v2.dart';
import 'supabase_config.dart';
import 'media_delivery_service.dart';
import 'supabase_read_cache.dart';
import 'guest_session.dart';

/// The first summaries page is safe to cache only inside one authenticated
/// account scope.  Keeping the actor in the key also protects against a
/// logout/login race where a short-lived entry is still within its TTL.
String chatV2SummaryCacheKey(String actorId, int limit) =>
    'chat-v2:summaries:$actorId:first:$limit';

abstract interface class ChatV2Source {
  Future<ChatSummaryPageV2> fetchSummaries({
    ChatSummaryCursorV2? cursor,
    int limit,
    bool force,
  });

  Future<ChatMessagePageV2> fetchMessages({
    required String threadId,
    ChatHistoryCursorV2? cursor,
    int limit,
  });

  Future<ChatDeltaPageV2> fetchChanges({
    required String threadId,
    required int afterChangeId,
    int limit,
  });

  Future<void> sendMessage({
    required ChatMessage message,
    required Map<String, dynamic> payload,
    required bool sendAsClub,
  });

  Future<void> markRead({
    required String threadId,
    required DateTime throughCreatedAt,
    required String throughMessageId,
    String scope,
  });
}

class SupabaseChatV2Service implements ChatV2Source {
  static const summaryFirstPageTtl = Duration(seconds: 30);
  static const _attachmentReferencePrefix = 'chat-attachment://';

  SupabaseClient? get client {
    if (!SupabaseConfig.isConfigured) return null;
    // Guest mode reuses the no-client path: no realtime channel is opened and
    // no RPC is issued, and the caller degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _requiredClient {
    final value = client;
    if (value == null) throw const ChatV2UnavailableException();
    return value;
  }

  @override
  Future<ChatSummaryPageV2> fetchSummaries({
    ChatSummaryCursorV2? cursor,
    int limit = 40,
    bool force = false,
  }) {
    final normalizedLimit = limit.clamp(1, 50).toInt();
    if (cursor != null) {
      return _fetchSummariesRemote(cursor: cursor, limit: normalizedLimit);
    }
    final actorId = client?.auth.currentUser?.id.trim() ?? '';
    // An unauthenticated caller cannot use the RPC. Avoid putting a failed or
    // anonymous result into a cache that may later be read by another actor.
    if (actorId.isEmpty) {
      return _fetchSummariesRemote(limit: normalizedLimit);
    }
    return supabaseReadCache.getOrFetch<ChatSummaryPageV2>(
      key: chatV2SummaryCacheKey(actorId, normalizedLimit),
      ttl: summaryFirstPageTtl,
      force: force,
      fetch: () => _fetchSummariesRemote(limit: normalizedLimit),
    );
  }

  Future<ChatSummaryPageV2> _fetchSummariesRemote({
    ChatSummaryCursorV2? cursor,
    required int limit,
  }) async {
    final response = await _requiredClient.rpc(
      'get_conversation_summaries_v2',
      params: {
        'p_limit': limit,
        'p_cursor_activity_at': cursor?.activityAt.toUtc().toIso8601String(),
        'p_cursor_thread_id': cursor?.threadId,
      },
    );
    return ChatSummaryPageV2.fromJson(_responseMap(response, 'summaries'));
  }

  @override
  Future<ChatMessagePageV2> fetchMessages({
    required String threadId,
    ChatHistoryCursorV2? cursor,
    int limit = 40,
  }) async {
    final normalizedLimit = limit.clamp(1, 50).toInt();
    final response = await _requiredClient.rpc(
      'get_messages_page_v2',
      params: {
        'p_thread_id': threadId,
        'p_limit': normalizedLimit,
        'p_cursor_created_at': cursor?.createdAt.toUtc().toIso8601String(),
        'p_cursor_id': cursor?.id,
      },
    );
    final json = _responseMap(response, 'message page');
    final messages = <ChatMessage>[];
    for (final raw in _mapList(json['items'])) {
      final message = ChatWireMessageV2(raw).toChatMessage();
      if (message == null) continue;
      messages.add(await _resolveVisibleAttachment(message));
    }
    return ChatMessagePageV2(
      threadId: json['thread_id']?.toString() ?? threadId,
      items: messages,
      hasMore: json['has_more'] == true,
      pageSize: _integer(json['page_size'], fallback: normalizedLimit),
      syncCursor: _integer(json['sync_cursor']),
      nextCursor: json['next_cursor'] is Map
          ? ChatHistoryCursorV2.fromJson(
              Map<String, dynamic>.from(json['next_cursor'] as Map),
            )
          : null,
    );
  }

  @override
  Future<ChatDeltaPageV2> fetchChanges({
    required String threadId,
    required int afterChangeId,
    int limit = 200,
  }) async {
    final response = await _requiredClient.rpc(
      'get_messages_since_v2',
      params: {
        'p_thread_id': threadId,
        'p_after_change_id': afterChangeId,
        'p_limit': limit.clamp(1, 500).toInt(),
      },
    );
    final page = ChatDeltaPageV2.fromJson(_responseMap(response, 'delta'));
    final changes = <ChatChangeV2>[];
    for (final change in page.changes) {
      final parsed =
          change.recordType == 'message' && change.operation != 'DELETE'
          ? ChatWireMessageV2(change.record).toChatMessage()
          : null;
      changes.add(
        parsed == null
            ? change
            : change.copyWith(message: await _resolveVisibleAttachment(parsed)),
      );
    }
    return page.copyWith(changes: changes);
  }

  @override
  Future<void> sendMessage({
    required ChatMessage message,
    required Map<String, dynamic> payload,
    required bool sendAsClub,
  }) async {
    await _requiredClient.rpc(
      'send_message_v2',
      params: {
        'p_thread_id': message.threadId,
        'p_message_id': message.id,
        'p_content': message.content,
        'p_message_kind': _databaseKind(message.kind),
        'p_payload': payload,
        'p_created_at': message.createdAt.toUtc().toIso8601String(),
        'p_send_as_club': sendAsClub,
      },
    );
    invalidateSummaries();
  }

  @override
  Future<void> markRead({
    required String threadId,
    required DateTime throughCreatedAt,
    required String throughMessageId,
    String scope = 'all',
  }) async {
    await _requiredClient.rpc(
      'mark_conversation_read_v2',
      params: {
        'p_thread_id': threadId,
        'p_through_created_at': throughCreatedAt.toUtc().toIso8601String(),
        'p_through_message_id': throughMessageId,
        'p_scope': scope,
      },
    );
    invalidateSummaries();
  }

  ChatMessage? messageFromRealtime(String table, Map<String, dynamic> row) {
    final normalized = Map<String, dynamic>.from(row);
    switch (table) {
      case 'direct_messages':
        final sender = normalized['sender_id']?.toString() ?? '';
        final receiver = normalized['receiver_id']?.toString() ?? '';
        if (sender.isEmpty || receiver.isEmpty) return null;
        final pair = [sender, receiver]..sort();
        normalized['thread_id'] = 'dm:${pair.join('|')}';
        break;
      case 'group_messages':
        final id = normalized['group_id']?.toString() ?? '';
        if (id.isEmpty) return null;
        normalized['thread_id'] = 'group:$id';
        break;
      case 'club_channel_messages':
        final id = normalized['club_id']?.toString() ?? '';
        if (id.isEmpty) return null;
        normalized['thread_id'] = 'club:$id';
        break;
      case 'club_inbox_messages':
        final id = normalized['thread_id']?.toString() ?? '';
        if (id.isEmpty) return null;
        normalized['inbox_id'] = id;
        normalized['thread_id'] = 'clubdm:$id';
        break;
      default:
        return null;
    }
    return ChatWireMessageV2(normalized).toChatMessage();
  }

  Future<ChatMessage> resolveRealtimeAttachment(ChatMessage message) =>
      _resolveVisibleAttachment(message);

  void invalidateSummaries() {
    supabaseReadCache.invalidateWhere(
      (key) => key.startsWith('chat-v2:summaries:'),
    );
  }

  void clearAccountCache() {
    supabaseReadCache.invalidateWhere((key) => key.startsWith('chat-v2:'));
    mediaDeliveryService.clearAllPrivate();
  }

  Future<ChatMessage> _resolveVisibleAttachment(ChatMessage message) async {
    final reference = message.attachmentPath?.trim() ?? '';
    if (!reference.startsWith(_attachmentReferencePrefix)) return message;
    // Keep the canonical reference stable. The visible chat image widget signs
    // the required rendition lazily, avoiding up to one signing request for
    // every off-screen image in a 40-message history page.
    return message;
  }
}

class ChatV2UnavailableException implements Exception {
  const ChatV2UnavailableException();

  @override
  String toString() => 'ChatV2UnavailableException: Supabase is unavailable';
}

Map<String, dynamic> _responseMap(Object? response, String name) {
  if (response is! Map) {
    throw FormatException('Chat v2 $name returned a non-object response');
  }
  return Map<String, dynamic>.from(response);
}

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
    : const [];

int _integer(Object? value, {int fallback = 0}) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? fallback,
};

String _databaseKind(ChatMessageKind kind) => switch (kind) {
  ChatMessageKind.postShare => 'post_share',
  _ => kind.name,
};

final supabaseChatV2Service = SupabaseChatV2Service();

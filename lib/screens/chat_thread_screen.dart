import 'dart:async' show unawaited;
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../models/chat_media_selection.dart';
import '../models/chat_message.dart';
import '../models/club.dart';
import '../models/user.dart';
import '../navigation/chat_page_route.dart';
import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/chat_attachment_staging.dart';
import '../services/chat_store.dart';
import '../services/club_admin_access.dart';
import '../services/club_community_info_controller.dart';
import '../services/locale_service.dart';
import '../services/mock_clubup_profile.dart';
import '../services/mock_data.dart';
import '../services/notification_inbox_service.dart';
import '../services/notification_service.dart';
import '../services/people_service.dart';
import '../services/image_cache_service.dart';
import '../services/image_aspect_ratio.dart';
import '../services/media_delivery_service.dart';
import '../services/theme_service.dart';
import '../services/user_profile_link.dart';
import '../services/user_state.dart';
import '../widgets/chat_campus_backdrop.dart';
import '../widgets/chats_design.dart';
import '../widgets/club_chat_design.dart';
import '../widgets/clubup_design.dart';
import '../widgets/chat_video_player.dart';
import '../widgets/club_avatar.dart';
import '../widgets/group_avatar_stack.dart';
import '../widgets/user_avatar.dart';
import '../widgets/user_profile_link_text.dart';
import '../widgets/app_network_image.dart';
import '../widgets/app_pressable.dart';
import '../widgets/shared_post_message_card.dart';
import '../widgets/shared_event_message_card.dart';
import '../widgets/shared_user_profile_message_card.dart';
import '../widgets/sent_message_entrance.dart';
import '../widgets/swipe_to_reply.dart';
import 'chat_camera_screen.dart';
import 'club_community_screen.dart';
import 'group_info_screen.dart';
import 'media_preview_screen.dart';
import 'user_profile_screen.dart';

/// What the composer's "+" sheet can attach to a student message.
enum _ChatAttachment { photo, camera }

const double _chatPortraitPhotoAspectRatio = 3 / 4;
const double _chatLandscapePhotoAspectRatio = 16 / 9;
const double _chatPhotoWidth = 200;

/// A single direct message, student-created group, or club community thread.
class ChatThreadScreen extends StatefulWidget {
  final String threadId;
  final User? recipient;
  final bool embedded;

  const ChatThreadScreen({
    super.key,
    required this.threadId,
    this.recipient,
    this.embedded = false,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen>
    with WidgetsBindingObserver {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  ChatTypingSession? _typingSession;
  Set<String> _lastTypingUserIds = const {};
  final Set<String> _requestedParticipantProfileIds = {};
  final Map<String, double> _photoAspectRatios = {};
  ClubCommunityInfoController? _communityInfo;
  final Set<String> _animatingSentMessageIds = {};
  ChatMessage? _replyingTo;

  // In-thread message search — `search-results` 110:84. Client-side over the
  // messages already loaded for this thread; nothing is queried remotely.
  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, GlobalKey> _searchAnchors = {};
  int _searchCursor = 0;

  String get _myId =>
      authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';

  bool get _isClub => ChatStore.isClubThread(widget.threadId);
  bool get _isClubInbox => ChatStore.isClubInboxThread(widget.threadId);
  bool get _isGroup => ChatStore.isGroupThread(widget.threadId);
  bool get _isDirect => ChatStore.isDirectThread(widget.threadId);

  Club? get _club {
    final clubId =
        ChatStore.clubIdOf(widget.threadId) ??
        chatStore.clubInboxForThread(widget.threadId)?.clubId;
    return clubId == null ? null : clubForId(clubId);
  }

  ClubInboxConversation? get _clubInbox =>
      chatStore.clubInboxForThread(widget.threadId);

  bool get _isClubInboxBoardViewer {
    final conversation = _clubInbox;
    final club = _club;
    if (conversation == null || club == null) return false;
    return club.boardMemberIds.contains(_myId) ||
        managedClubForAdmin(_myId)?.id == conversation.clubId;
  }

  User? _userForId(String userId) {
    final passedRecipient = widget.recipient;
    if (passedRecipient != null && passedRecipient.id == userId) {
      return passedRecipient;
    }
    final currentUser = authService.currentUser;
    if (currentUser != null && currentUser.id == userId) return currentUser;
    final cachedIndex = peopleService.cachedPeople.indexWhere(
      (user) => user.id == userId,
    );
    if (cachedIndex != -1) return peopleService.cachedPeople[cachedIndex];
    final knownIndex = users.indexWhere((user) => user.id == userId);
    if (knownIndex != -1) return users[knownIndex];
    return null;
  }

  User? get _peer {
    final peerId = ChatStore.dmPeerOf(widget.threadId, _myId);
    return peerId == null ? null : _userForId(peerId);
  }

  Future<void> _openSharedUserProfile(String userIdentifier) async {
    final user = await resolveUserProfileLink(userIdentifier);
    if (!mounted || user == null) return;
    await Navigator.of(
      context,
    ).push(ChatPageRoute<void>(builder: (_) => UserProfileScreen(user: user)));
    if (mounted) _markVisibleMessagesSeen();
  }

  static const List<Color> _clubColors = [
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  Color _colorForClub(String clubId) {
    final idx = clubOrdinal(clubId);
    return _clubColors[(idx < 0 ? 0 : idx) % _clubColors.length];
  }

  @override
  void initState() {
    super.initState();
    final club = _club;
    if (club != null) {
      _communityInfo = ClubCommunityInfoController(
        clubId: club.id,
        fallbackMemberCount: clubMemberCount(club.id),
        fallbackMemberIds: clubMembers(club.id).map((member) => member.id),
      );
    }
    WidgetsBinding.instance.addObserver(this);
    themeService.addListener(_onEnvChanged);
    localeService.addListener(_onEnvChanged);
    chatStore.addListener(_onStoreChanged);
    _inputController.addListener(_onTypingDraftChanged);
    _inputFocusNode.addListener(_onTypingFocusChanged);
    _scrollController.addListener(_onMessageScroll);
    notificationInboxService.addListener(_onNotificationInboxChanged);
    // Post-frame: both can notifyListeners, which is illegal while this
    // route is still mounting mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final canAccess = chatStore.canAccessThread(widget.threadId, _myId);
      if (_isClub && (canAccess || authService.isStudentSession)) {
        unawaited(_communityInfo?.start());
      }
      if (!canAccess) return;
      if (!_isClub) {
        _typingSession = chatStore.openTypingSession(
          threadId: widget.threadId,
          actorId: _myId,
        );
        _typingSession
          ?..updateDraft(_inputController.text)
          ..updateFocus(_inputFocusNode.hasFocus);
        _lastTypingUserIds = chatStore
            .typingUserIds(widget.threadId, excluding: _myId)
            .toSet();
      }
      unawaited(chatStore.startChatV2Sync(_myId));
      unawaited(chatStore.loadInitialMessagesV2(widget.threadId));
      if (_isDirect) {
        final peerId = ChatStore.dmPeerOf(widget.threadId, _myId);
        if (peerId != null) {
          chatStore.ensureDirectThread(_myId, peerId);
          unawaited(_hydratePeerProfile(peerId));
        }
      } else if (_isClub || _isGroup || _isClubInbox) {
        _hydrateVisibleParticipants();
      }
      // Only a visible, foreground conversation may create Seen receipts.
      _markVisibleMessagesSeen();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeService.removeListener(_onEnvChanged);
    localeService.removeListener(_onEnvChanged);
    chatStore.removeListener(_onStoreChanged);
    _inputController.removeListener(_onTypingDraftChanged);
    _inputFocusNode.removeListener(_onTypingFocusChanged);
    _scrollController.removeListener(_onMessageScroll);
    notificationInboxService.removeListener(_onNotificationInboxChanged);
    _typingSession?.dispose();
    _communityInfo?.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(chatStore.reconcileThreadV2(widget.threadId));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDirect) {
          final peerId = ChatStore.dmPeerOf(widget.threadId, _myId);
          if (peerId != null && _userForId(peerId) == null) {
            unawaited(_hydratePeerProfile(peerId));
          }
        } else {
          _requestedParticipantProfileIds.removeWhere(
            (id) => _userForId(id) == null,
          );
          _hydrateVisibleParticipants();
        }
        _markVisibleMessagesSeen();
      });
    } else {
      _typingSession?.stop();
    }
  }

  void _onTypingDraftChanged() {
    _typingSession?.updateDraft(_inputController.text);
  }

  void _onTypingFocusChanged() {
    _typingSession?.updateFocus(_inputFocusNode.hasFocus);
  }

  void _onMessageScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // reverse:true: the oldest loaded item is at maxScrollExtent. One guarded
    // request is issued only when the viewport approaches that boundary.
    if (position.maxScrollExtent - position.pixels <=
        position.viewportDimension * 0.75) {
      unawaited(chatStore.loadOlderMessagesV2(widget.threadId));
    }
  }

  void _markVisibleMessagesSeen() {
    if (!mounted) return;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    // A club room is read one lane at a time by the ClubCommunityScreen this
    // route delegates to; marking the whole thread here would wipe both of the
    // Board / Chat counts the moment the room opens.
    if (!_isClub) chatStore.markThreadRead(widget.threadId, _myId);
    _dismissVisibleChatNotifications();
  }

  void _onNotificationInboxChanged() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    _dismissVisibleChatNotifications();
  }

  void _dismissVisibleChatNotifications() {
    final userId = _myId;
    if (userId.isEmpty) return;
    userState.markChatThreadNotificationsRead(
      threadId: widget.threadId,
      userId: userId,
    );
    unawaited(
      notificationInboxService.markChatThreadRead(
        threadId: widget.threadId,
        userId: userId,
      ),
    );
    unawaited(
      notificationService.cancelChatNotifications(
        threadId: widget.threadId,
        currentUserId: userId,
      ),
    );
  }

  void _onEnvChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _hydratePeerProfile(String peerId) async {
    await peopleService.hydrateProfilesByIds([peerId]);
    if (mounted) setState(() {});
  }

  void _hydrateVisibleParticipants() {
    if ((!_isClub && !_isGroup && !_isClubInbox) ||
        !chatStore.canAccessThread(widget.threadId, _myId)) {
      return;
    }
    final participantIds =
        <String>{
            if (_isGroup) ...chatStore.groupParticipants(widget.threadId),
            if (_clubInbox case final inbox?) inbox.profileId,
            ...chatStore
                .messagesFor(widget.threadId, viewerId: _myId)
                .map((message) => chatStore.senderIdForViewer(message, _myId)),
            ...chatStore.typingUserIds(widget.threadId, excluding: _myId),
          }
          ..remove(_myId)
          ..removeAll(_requestedParticipantProfileIds);
    if (participantIds.isEmpty) return;
    _requestedParticipantProfileIds.addAll(participantIds);
    unawaited(
      peopleService.hydrateProfilesByIds(participantIds).then((_) {
        _requestedParticipantProfileIds.removeWhere(
          (id) => _userForId(id) == null,
        );
        if (mounted) setState(() {});
      }),
    );
  }

  /// Messages arriving while the thread is open are read immediately.
  /// Safe from notify loops: markThreadRead only notifies when something
  /// actually was unread.
  void _onStoreChanged() {
    if (!mounted) return;
    if (!chatStore.canAccessThread(widget.threadId, _myId)) {
      _typingSession?.dispose();
      _typingSession = null;
      chatStore.clearTypingThread(widget.threadId);
    }
    final typingNow = chatStore
        .typingUserIds(widget.threadId, excluding: _myId)
        .toSet();
    final typingAppeared = typingNow.difference(_lastTypingUserIds).isNotEmpty;
    _lastTypingUserIds = typingNow;
    if (typingAppeared) _revealTypingIfNearLatest();
    _hydrateVisibleParticipants();
    _markVisibleMessagesSeen();
    final rateLimitMessage = chatStore.takeRateLimitFailureMessage();
    final permanentFailure = chatStore.takePermanentUploadFailureMessage();
    final attachmentFailed = chatStore.takeAttachmentUploadFailure();
    if (permanentFailure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(permanentFailure)));
    } else if (rateLimitMessage != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(rateLimitMessage)));
    }
    if (permanentFailure == null &&
        rateLimitMessage == null &&
        attachmentFailed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(S.photoSavedLocallyUploadFailed)),
        );
    }
  }

  void _revealTypingIfNearLatest() {
    final wasNearLatest =
        !_scrollController.hasClients ||
        _scrollController.position.pixels <= 80;
    if (!wasNearLatest) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients ||
          _scrollController.position.pixels > 80) {
        return;
      }
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Sends the composer draft, or [text] when a starter chip was tapped.
  void _send({String? text}) {
    _typingSession?.stop();
    final sent = chatStore.sendMessage(
      threadId: widget.threadId,
      senderId: _myId,
      content: text ?? _inputController.text,
      replyToMessageId: _replyingTo?.id,
    );
    if (sent == null) return;
    if (text == null) _inputController.clear();
    if (mounted) {
      setState(() {
        _replyingTo = null;
        _animatingSentMessageIds.add(sent.id);
      });
    }
    _scrollToLatest();
  }

  void _finishSentMessageEntrance(String messageId) {
    if (!mounted || !_animatingSentMessageIds.contains(messageId)) return;
    setState(() => _animatingSentMessageIds.remove(messageId));
  }

  void _scrollToLatest() {
    // reverse:true list — offset 0 is the newest message at the bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      // Flying back from deep in the history is an unreadable blur at this
      // duration, so close the gap first and animate only the last screenful.
      final animatedTravel = position.viewportDimension * 1.5;
      if (position.pixels > animatedTravel) {
        _scrollController.jumpTo(animatedTravel);
      }
      _scrollController.animateTo(
        0,
        duration: sentMessageEntranceDuration,
        curve: sentMessageEntranceCurve,
      );
    });
  }

  // ── Attachments ─────────────────────────────────────────────────────────────

  Future<void> _openAttachSheet() async {
    final picked = await showModalBottomSheet<_ChatAttachment>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        key: const ValueKey('chat-attach-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              S.attachToMessage,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 6),
            // Live capture moved onto the composer's camera button, so the
            // sheet only offers media that already exists in the library.
            for (final (attachment, icon, label) in [
              (
                _ChatAttachment.photo,
                Icons.photo_library_outlined,
                S.attachMedia,
              ),
            ])
              InkWell(
                key: ValueKey('chat-attach-${attachment.name}'),
                onTap: () => Navigator.pop(sheetContext, attachment),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.lightRed,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          icon,
                          size: 17,
                          color: AppColors.primaryRed,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _pickAttachment(picked);
  }

  /// Opens the in-app camera. The photo comes back upright and, when the front
  /// lens took it, mirrored the way the viewfinder showed it.
  Future<XFile?> _captureWithCamera() => Navigator.of(
    context,
  ).push<XFile>(ChatPageRoute(builder: (_) => const ChatCameraScreen()));

  Future<void> _pickAttachment(_ChatAttachment attachment) async {
    while (mounted) {
      late final List<XFile> picked;
      try {
        picked = switch (attachment) {
          _ChatAttachment.photo => await ImagePicker().pickMultipleMedia(
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 88,
            limit: 30,
          ),
          // The in-app camera, not the system one: iOS's picker always inserts
          // its own Retake/Use Photo step before handing the file back, and this
          // screen already confirms a photo in MediaPreviewScreen. The camera
          // screen also knows which lens fired, so a selfie comes back mirrored
          // to match the viewfinder instead of guessed at from EXIF.
          _ChatAttachment.camera => [?await _captureWithCamera()],
        };
      } catch (_) {
        // Only the library branch can throw now; the camera screen reports its
        // own failures, which is what makes this message accurate.
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(S.mediaSelectionFailed)));
        }
        return;
      }
      if (picked.isEmpty) return;
      if (!mounted) return;
      final inspected = await inspectChatMediaFiles(picked);
      if (!mounted) return;
      if (inspected.rejectedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.mediaSelectionRejected(inspected.rejectedCount)),
          ),
        );
      }
      if (inspected.items.isEmpty) return;

      final result = await Navigator.of(context).push<MediaPreviewResult>(
        ChatPageRoute(
          builder: (_) => MediaPreviewScreen(
            initialMedia: inspected.items,
            initialCaption: _inputController.text.trim(),
          ),
        ),
      );
      if (!mounted) return;
      if (result == null) {
        // Dismissing a captured photo means retake; cancelling the camera
        // itself still exits through the empty selection above.
        if (attachment == _ChatAttachment.camera) continue;
        return;
      }
      await _sendAttachments(result);
      return;
    }
  }

  Future<void> _sendAttachments(MediaPreviewResult result) async {
    final sentMessages = <ChatMessage>[];
    var stagingFailed = false;
    for (final media in result.items) {
      late final String stagedPath;
      try {
        stagedPath = await stageChatAttachment(
          media.file.path,
          sourceName: media.file.name,
        );
      } on Object {
        stagingFailed = true;
        continue;
      }
      final isFirst = sentMessages.isEmpty;
      final sent = chatStore.sendMessage(
        threadId: widget.threadId,
        senderId: _myId,
        content: isFirst ? result.caption : '',
        kind: media.type == ChatMediaType.image
            ? ChatMessageKind.photo
            : ChatMessageKind.file,
        attachmentPath: stagedPath,
        attachmentName: media.file.name,
        attachmentSize: media.sizeBytes,
        replyToMessageId: isFirst ? _replyingTo?.id : null,
      );
      if (sent != null) sentMessages.add(sent);
    }
    if (!mounted) return;
    if (sentMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            stagingFailed ? S.couldNotAttachPhoto : S.mediaSendFailed,
          ),
        ),
      );
      return;
    }
    _inputController.clear();
    if (mounted) {
      setState(() {
        _replyingTo = null;
        _animatingSentMessageIds.addAll(
          sentMessages.map((message) => message.id),
        );
      });
    }
    _scrollToLatest();
  }

  // ── Reactions ───────────────────────────────────────────────────────────────

  static const _quickReactions = ['👍', '❤️', '🎉', '👏', '😂', '🙌'];

  Future<void> _confirmDeleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.deleteMessage),
        content: Text(S.deleteMessageMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              S.delete,
              style: TextStyle(color: AppColors.primaryRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      chatStore.deleteMessage(messageId: message.id, userId: _myId);
    }
  }

  void _openMessageInfo(ChatMessage originalMessage) {
    // Receipt identities and timestamps are sender-only. Keep this guard here
    // as well as at each UI entry point so future callers cannot accidentally
    // expose message information for somebody else's message.
    if (!chatStore.isMessageOwner(originalMessage, _myId)) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AnimatedBuilder(
        animation: chatStore,
        builder: (context, _) {
          // Re-read on every ChatStore notification so a Realtime receipt can
          // move from Delivered to Read while this sheet remains open.
          final message =
              chatStore.messageById(originalMessage.id) ?? originalMessage;
          final readReceipts =
              message.receipts
                  .where(
                    (receipt) =>
                        receipt.userId != message.senderId &&
                        receipt.seenAt != null,
                  )
                  .toList(growable: false)
                ..sort((a, b) => b.seenAt!.compareTo(a.seenAt!));
          final deliveredReceipts =
              message.receipts
                  .where(
                    (receipt) =>
                        receipt.userId != message.senderId &&
                        receipt.seenAt == null &&
                        receipt.deliveredAt != null,
                  )
                  .toList(growable: false)
                ..sort((a, b) => b.deliveredAt!.compareTo(a.deliveredAt!));

          return Container(
            key: const ValueKey('chat-message-info-sheet'),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
            ),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    S.messageInfo,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_isDirect) ...[
                    _directReceiptRow(
                      icon: Icons.done_all_rounded,
                      label: S.deliveredAt(
                        _receiptTimestamp(message.deliveredAt),
                      ),
                      color: AppColors.secondaryText,
                    ),
                    if (message.seenAt case final seenAt?)
                      _directReceiptRow(
                        icon: Icons.done_all_rounded,
                        label: S.readAt(_receiptTimestamp(seenAt)),
                        color: AppColors.primaryRed,
                      ),
                  ] else if (_isGroup) ...[
                    _receiptSection(
                      title: S.readBy,
                      receipts: readReceipts,
                      timestampFor: (receipt) => receipt.seenAt!,
                    ),
                    const SizedBox(height: 14),
                    _receiptSection(
                      title: S.deliveredTo,
                      receipts: deliveredReceipts,
                      timestampFor: (receipt) => receipt.deliveredAt!,
                    ),
                  ],
                  Divider(height: 28, color: AppColors.divider),
                  if (chatStore.canWriteThread(widget.threadId, _myId))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.reply_rounded,
                        color: AppColors.primaryRed,
                      ),
                      title: Text(
                        S.reply,
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _beginReply(message);
                      },
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.primaryRed,
                    ),
                    title: Text(
                      S.deleteMessage,
                      style: TextStyle(
                        color: AppColors.primaryRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_confirmDeleteMessage(message));
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _directReceiptRow({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _receiptSection({
    required String title,
    required List<MessageReceipt> receipts,
    required DateTime Function(MessageReceipt receipt) timestampFor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        if (receipts.isEmpty)
          Padding(
            key: ValueKey('empty-message-receipts-$title'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              S.noOneYet,
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          for (final receipt in receipts)
            Builder(
              builder: (context) {
                final name = _senderInfo(receipt.userId).$1;
                return ListTile(
                  key: ValueKey('message-receipt-${receipt.userId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(
                    userId: receipt.userId,
                    name: name.isEmpty ? receipt.userId : name,
                    size: 38,
                    fontSize: 14,
                  ),
                  title: Text(
                    name.isEmpty ? receipt.userId : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: Text(
                    _receiptTimestamp(timestampFor(receipt)),
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
      ],
    );
  }

  void _openMessageLongPress(ChatMessage message) {
    if (chatStore.isMessageOwner(message, _myId) && (_isDirect || _isGroup)) {
      _openMessageInfo(message);
      return;
    }
    _openReactionPicker(message);
  }

  void _openReactionPicker(ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        key: const ValueKey('chat-reaction-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final emoji in _quickReactions)
                  GestureDetector(
                    key: ValueKey('chat-reaction-option-$emoji'),
                    onTap: () {
                      chatStore.toggleReaction(
                        messageId: message.id,
                        userId: _myId,
                        emoji: emoji,
                      );
                      Navigator.pop(sheetContext);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            (message.reactions[emoji] ?? const []).contains(
                              _myId,
                            )
                            ? AppColors.lightRed
                            : AppColors.surfaceAlt,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.glassEdge),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: AppColors.divider),
            if (chatStore.canWriteThread(widget.threadId, _myId))
              Material(
                color: Colors.transparent,
                child: ListTile(
                  key: ValueKey('chat-reply-message-${message.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.reply_rounded,
                    color: AppColors.primaryRed,
                  ),
                  title: Text(
                    S.reply,
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _beginReply(message);
                  },
                ),
              ),
            if (chatStore.isMessageOwner(message, _myId)) ...[
              Material(
                color: Colors.transparent,
                child: ListTile(
                  key: ValueKey('chat-delete-message-${message.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.primaryRed,
                  ),
                  title: Text(
                    S.deleteMessage,
                    style: TextStyle(
                      color: AppColors.primaryRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_confirmDeleteMessage(message));
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _beginReply(ChatMessage message) {
    setState(() => _replyingTo = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  // ── Sender identity ─────────────────────────────────────────────────────────

  /// Display name + whether the sender is a club-admin account.
  (String, bool) _senderInfo(String senderId) {
    final club = _club;
    if (club != null &&
        (senderId == club.id ||
            club.adminUserIds.contains(senderId) ||
            managedClubForAdmin(senderId)?.id == club.id)) {
      return (club.name, true);
    }
    final user = _userForId(senderId);
    if (user != null) {
      return (userState.displayNameFor(senderId, user.name), false);
    }
    final aIdx = clubAdmins.indexWhere((a) => a.id == senderId);
    if (aIdx != -1) return (clubAdmins[aIdx].name, true);
    if (senderId == appAdmin.id) return (appAdmin.name, true);
    return (userState.displayNameFor(senderId, ''), false);
  }

  void _openGroupInfo() {
    Navigator.push<GroupInfoOutcome>(
      context,
      ChatPageRoute(
        builder: (_) => GroupInfoScreen(threadId: widget.threadId, myId: _myId),
      ),
    ).then((outcome) {
      if (!mounted) return;
      switch (outcome) {
        case GroupInfoOutcome.left:
          Navigator.pop(context);
        case GroupInfoOutcome.search:
          // `group-info`'s Search quick action lands on `search-results`,
          // which lives in the thread.
          _openThreadSearch();
        case null:
          _markVisibleMessagesSeen();
      }
    });
  }

  void _openDirectChatById(String userId) {
    final user = _userForId(userId);
    if (user == null) return;
    final threadId = chatStore.ensureDirectThread(_myId, userId);
    if (threadId == null) return;
    Navigator.push(
      context,
      ChatPageRoute(
        builder: (_) => ChatThreadScreen(threadId: threadId, recipient: user),
      ),
    ).then((_) => _markVisibleMessagesSeen());
  }

  // ── CHATS handoff: the student thread ──────────────────────────────────────
  // `chat-dm` 102:7, `chat-group` 102:123, `chats-clubs` 225:5 and
  // `search-results` 110:84. Flat bubbles on a flat page: no wallpaper, no
  // gradient or shadow, and a 36pt composer. The active UI adds a restrained
  // tail to the bottom bubble of each sender run.
  //
  // The `CLUB CHATS` section (label `543:32`) added the club side of one of
  // these: `admin-direct-messages` 335:255 / 331:438 is a private inbox read
  // by the club rather than by the student, and draws through the same header
  // and bubbles. It is the only thread a club login opens — everything else it
  // can reach is the room itself, which `ClubCommunityScreen` draws.

  bool get _designChat {
    if (widget.embedded) return false;
    if (authService.isStudentSession) return true;
    final admin = authService.currentAdmin;
    return _isClubInbox && admin != null && !isClubUpAdmin(admin);
  }

  double _designBubbleMaxWidth(BuildContext context, {required bool inset}) {
    final available = MediaQuery.sizeOf(context).width - 32 - (inset ? 36 : 0);
    return available * (inset ? 0.83 : 0.776);
  }

  List<ChatMessage> _designSearchMatches(List<ChatMessage> messages) {
    final needle = _searchController.text.trim().toLowerCase();
    if (needle.isEmpty) return const <ChatMessage>[];
    return messages
        .where((m) => m.content.toLowerCase().contains(needle))
        .toList();
  }

  void _openThreadSearch() {
    setState(() {
      _searchOpen = true;
      _searchCursor = 0;
      _searchController.clear();
    });
  }

  void _closeThreadSearch() {
    setState(() {
      _searchOpen = false;
      _searchCursor = 0;
      _searchController.clear();
      _searchAnchors.clear();
    });
  }

  void _stepSearch(int delta, List<ChatMessage> matches) {
    if (matches.isEmpty) return;
    final next = (_searchCursor + delta) % matches.length;
    setState(() => _searchCursor = next < 0 ? next + matches.length : next);
    final anchor = _searchAnchors[matches[_searchCursor].id];
    final anchorContext = anchor?.currentContext;
    if (anchorContext != null) {
      Scrollable.ensureVisible(
        anchorContext,
        alignment: 0.4,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildDesignThread() {
    return Scaffold(
      backgroundColor: ChatsColors.background,
      resizeToAvoidBottomInset: true,
      body: ListenableBuilder(
        listenable: Listenable.merge([chatStore, userState, ?_communityInfo]),
        builder: (context, _) {
          if (!chatStore.canAccessThread(widget.threadId, _myId)) {
            return SafeArea(
              bottom: false,
              child: _buildUnavailableConversation(),
            );
          }
          final messages = chatStore.messagesFor(
            widget.threadId,
            viewerId: _myId,
          );
          final typing = chatStore.typingUserIds(
            widget.threadId,
            excluding: _myId,
          );
          final matches = _searchOpen
              ? _designSearchMatches(messages)
              : const <ChatMessage>[];
          return Column(
            children: [
              if (_searchOpen)
                _buildDesignSearchBar(matches)
              else
                _buildDesignThreadHeader(),
              Expanded(
                child: messages.isEmpty && typing.isEmpty
                    ? _buildNewChatIntro()
                    : _buildDesignMessageList(messages, matches, typing),
              ),
              if (!_searchOpen)
                ChatComposerBar(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  enabled: chatStore.canWriteThread(widget.threadId, _myId),
                  hint: S.typeMessage,
                  // The paperclip's sheet only offers library media; a live
                  // capture lives on the trailing camera button, which morphs
                  // into the send button while a draft exists.
                  onAttach: _openAttachSheet,
                  onSend: _send,
                  onCameraCapture: () =>
                      _pickAttachment(_ChatAttachment.camera),
                  banner: _replyingTo == null
                      ? null
                      : _designReplyBanner(_replyingTo!),
                )
              else
                const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildDesignThreadHeader() {
    if (_isGroup) return _buildDesignGroupHeader();
    if (_isClubInbox) return _buildDesignClubInboxHeader();
    final peer = _peer;
    final peerId = ChatStore.dmPeerOf(widget.threadId, _myId);
    final name = peer != null
        ? userState.displayNameFor(peer.id, peer.name)
        : '';
    // `chat-dm` 102:18 — a chevron, a 38pt avatar and the name. The peer's
    // programme, which the previous header carried, is not on the frame.
    return _designHeaderShell(
      tapKey: const ValueKey('dm-chat-header'),
      onTap: peer == null ? null : () => _openSharedUserProfile(peer.id),
      leading: UserAvatar(
        userId: peer?.id ?? peerId ?? '',
        name: peer?.name ?? '',
        size: 38,
        fontSize: 15,
      ),
      leadingWidth: 38,
      title: name,
    );
  }

  Widget _buildDesignGroupHeader() {
    final memberIds = chatStore.groupParticipants(widget.threadId);
    final visibleIds = memberIds.where((id) => id != _myId).toList();
    // `chat-group` 102:138 — the stack is 48 wide inside a 38 tall box.
    return _designHeaderShell(
      tapKey: const ValueKey('group-chat-header'),
      onTap: _openGroupInfo,
      leading: GroupAvatarStack(
        memberIds: visibleIds,
        nameForUser: (id) => _senderInfo(id).$1,
        photoPath: chatStore.groupForThread(widget.threadId)?.photoUrl,
        size: 38,
      ),
      leadingWidth: 48,
      title: chatStore.groupDisplayName(widget.threadId, _myId),
      subtitle: S.chatsFriendsCount(memberIds.length),
    );
  }

  Widget _buildDesignClubInboxHeader() {
    final conversation = _clubInbox;
    final club = _club;
    final showingStudent =
        conversation != null && conversation.profileId != _myId;
    final student = showingStudent ? _userForId(conversation.profileId) : null;
    final title = showingStudent
        ? userState.displayNameFor(conversation.profileId, student?.name ?? '')
        : club?.name ?? '';
    return _designHeaderShell(
      tapKey: const ValueKey('club-inbox-profile-header'),
      leading: showingStudent
          ? UserAvatar(
              userId: conversation.profileId,
              name: title,
              size: 38,
              fontSize: 15,
            )
          : club == null
          ? const SizedBox(width: 38, height: 38)
          : ClubAvatar(
              clubId: club.id,
              clubName: club.name,
              color: _colorForClub(club.id),
              imageUrl: club.logoUrl,
              size: 38,
              fontSize: 15,
              shape: 'circle',
            ),
      leadingWidth: 38,
      title: title,
      subtitle: S.chatsDmWithAdmins,
      // `234:412` draws this as a dropdown. The app has exactly one lane for a
      // club inbox — the private one — so it is a badge here rather than a
      // switcher that would have nothing to switch to.
      trailing: Container(
        key: const ValueKey('club-inbox-lane-badge'),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: ChatsColors.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: ChatsColors.onAccent,
            ),
            const SizedBox(width: 8),
            Text(
              S.chatsDirectLane,
              style: figtree(
                size: 13,
                weight: FontWeight.w700,
                color: ChatsColors.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The 62pt bar `chat-dm` 102:18 and `chat-group` 102:134 share: a hairline
  /// underneath, no fill of its own, no shadow.
  Widget _designHeaderShell({
    required Widget leading,
    required double leadingWidth,
    required String title,
    String? subtitle,
    Widget? trailing,
    Key? tapKey,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
      decoration: BoxDecoration(
        color: ChatsColors.background,
        border: Border(bottom: BorderSide(color: ChatsColors.border)),
      ),
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Semantics(
              button: true,
              label: MaterialLocalizations.of(context).backButtonTooltip,
              child: GestureDetector(
                key: const ValueKey('chat-thread-back'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.maybePop(context),
                child: SizedBox(
                  width: 24,
                  height: 62,
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 24,
                    color: ChatsColors.backIcon,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                key: tapKey,
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Row(
                  children: [
                    SizedBox(width: leadingWidth, height: 38, child: leading),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: figtree(
                              size: 15,
                              weight: FontWeight.w700,
                              color: ChatsColors.text,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: figtree(
                                size: 11,
                                weight: FontWeight.w500,
                                color: ChatsColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ] else
              GestureDetector(
                key: const ValueKey('chat-thread-search-button'),
                behavior: HitTestBehavior.opaque,
                onTap: _openThreadSearch,
                child: SizedBox(
                  width: 36,
                  height: 62,
                  child: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: ChatsColors.muted,
                  ),
                ),
              ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  /// `search-results` 110:95 + 110:104 — the header becomes a field with a
  /// Cancel, and a 46pt panel below counts the hits and steps through them.
  Widget _buildDesignSearchBar(List<ChatMessage> matches) {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
      decoration: BoxDecoration(
        color: ChatsColors.background,
        border: Border(bottom: BorderSide(color: ChatsColors.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 60,
            child: Row(
              children: [
                const SizedBox(width: 16),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeThreadSearch,
                  child: SizedBox(
                    width: 24,
                    height: 60,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 24,
                      color: ChatsColors.backIcon,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: ChatsColors.fill,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 14,
                          color: ChatsColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('chat-thread-search-field'),
                            controller: _searchController,
                            autofocus: true,
                            onChanged: (_) => setState(() => _searchCursor = 0),
                            style: figtree(
                              size: 13,
                              weight: FontWeight.w500,
                              color: ChatsColors.text,
                            ),
                            decoration: InputDecoration(
                              hintText: S.chatsSearchMessages,
                              hintStyle: figtree(
                                size: 13,
                                weight: FontWeight.w400,
                                color: ChatsColors.muted,
                              ),
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (hasQuery)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              _searchController.clear();
                              _searchCursor = 0;
                            }),
                            child: Icon(
                              Icons.cancel_rounded,
                              size: 14,
                              color: ChatsColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  key: const ValueKey('chat-thread-search-cancel'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeThreadSearch,
                  child: Text(
                    S.cancel,
                    style: figtree(
                      size: 13,
                      weight: FontWeight.w600,
                      color: ChatsColors.accentText,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          if (hasQuery)
            SizedBox(
              height: 46,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Text(
                    matches.isEmpty
                        ? S.chatsNoResultsFound
                        : S.chatsResultsFound(matches.length),
                    style: figtree(
                      size: 12,
                      weight: FontWeight.w600,
                      color: ChatsColors.muted,
                    ),
                  ),
                  const Spacer(),
                  _searchStepButton(
                    Icons.keyboard_arrow_up_rounded,
                    matches.isEmpty ? null : () => _stepSearch(-1, matches),
                    const ValueKey('chat-thread-search-prev'),
                  ),
                  const SizedBox(width: 16),
                  _searchStepButton(
                    Icons.keyboard_arrow_down_rounded,
                    matches.isEmpty ? null : () => _stepSearch(1, matches),
                    const ValueKey('chat-thread-search-next'),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchStepButton(IconData icon, VoidCallback? onTap, Key key) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ChatsColors.fill,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null ? ChatsColors.muted : ChatsColors.accentText,
        ),
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────

  Widget _buildDesignMessageList(
    List<ChatMessage> messages,
    List<ChatMessage> matches,
    List<String> typing,
  ) {
    final matchIds = matches.map((m) => m.id).toSet();
    _searchAnchors.removeWhere((id, _) => !matchIds.contains(id));
    for (final id in matchIds) {
      _searchAnchors.putIfAbsent(id, GlobalKey.new);
    }
    final items = <Widget>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final prev = i > 0 ? messages[i - 1] : null;
      final next = i < messages.length - 1 ? messages[i + 1] : null;
      if (prev == null || !_sameDay(prev.createdAt, m.createdAt)) {
        items.add(ChatDayDivider(label: _dayLabel(m.createdAt)));
      }
      final senderId = chatStore.senderIdForViewer(m, _myId);
      final nextSenderId = next == null
          ? null
          : chatStore.senderIdForViewer(next, _myId);
      final lastOfRun =
          next == null ||
          nextSenderId != senderId ||
          !_sameDay(next.createdAt, m.createdAt);
      items.add(
        SentMessageEntrance(
          key: ValueKey('sent-message-entrance-${m.id}'),
          animate: _animatingSentMessageIds.contains(m.id),
          onCompleted: () => _finishSentMessageEntrance(m.id),
          child: _designBubbleRow(
            m,
            anchor: _searchAnchors[m.id],
            showTail: lastOfRun,
          ),
        ),
      );
    }
    if (typing.isNotEmpty) items.add(_typingBubble(typing));
    final childIndexByKey = <Key, int>{
      for (var i = 0; i < items.length; i++)
        ?items[i].key: items.length - 1 - i,
    };
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: items.length,
      findChildIndexCallback: (key) => childIndexByKey[key],
      itemBuilder: (context, i) => items[items.length - 1 - i],
    );
  }

  /// One message. Sender labels and avatars remain visible on every incoming
  /// group message, while only the bottom bubble in a sender run gets a tail.
  Widget _designBubbleRow(
    ChatMessage m, {
    GlobalKey? anchor,
    required bool showTail,
  }) {
    final mine = chatStore.isMessageOwner(m, _myId);
    final senderId = chatStore.senderIdForViewer(m, _myId);
    final (senderName, senderIsAdmin) = _senderInfo(senderId);
    final club = _club;
    final showAvatar = _isGroup && !mine;
    final showSenderName = (_isGroup || _isClubInbox) && !mine;
    final linkedEventId = m.linkedEventId;
    final hasEventPreview = linkedEventId != null;
    final userLinkMatches = UserProfileLink.matchesIn(m.content);
    final sharedUserLink = userLinkMatches.isEmpty
        ? null
        : userLinkMatches.first;
    final isStandaloneUserLink =
        sharedUserLink != null &&
        UserProfileLink.isStandalone(m.content, sharedUserLink);
    final hasText =
        m.content.trim().isNotEmpty &&
        !hasEventPreview &&
        !isStandaloneUserLink;
    final photoPath = m.kind == ChatMessageKind.photo ? m.attachmentPath : null;
    final attachedFilePath = m.kind == ChatMessageKind.file
        ? m.attachmentPath
        : null;
    final videoPath =
        attachedFilePath != null &&
            isVideoMediaPath(m.attachmentName ?? attachedFilePath)
        ? attachedFilePath
        : null;
    final filePath = videoPath == null ? attachedFilePath : null;
    final hasMedia = photoPath != null || videoPath != null || filePath != null;

    final bubble = ChatBubbleShell(
      key: ValueKey('chat-message-bubble-${m.id}'),
      mine: mine,
      showTail: showTail,
      maxWidth: _designBubbleMaxWidth(context, inset: showAvatar),
      padding: photoPath != null
          ? const EdgeInsets.all(2)
          : hasMedia
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: _messageBodyWithTime(
        message: m,
        mine: mine,
        designChat: true,
        hasPhoto: photoPath != null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.replyToMessageId != null)
              _designReplyQuote(m, mine: mine, hasBody: hasMedia || hasText),
            if (m.kind == ChatMessageKind.postShare && m.sharedPostId != null)
              SharedPostMessageCard(
                postId: m.sharedPostId!,
                onDarkBackground: mine,
              ),
            if (hasEventPreview)
              SharedEventMessageCard(
                eventId: linkedEventId,
                onDarkBackground: mine,
              ),
            if (photoPath != null)
              _photoAttachmentWithTime(m, mine: mine, designChat: true),
            if (videoPath != null) _videoAttachment(videoPath),
            if (filePath != null) _fileAttachment(m, mine: mine),
            if (hasText)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  hasMedia ? 10 : 0,
                  hasMedia ? 8 : 0,
                  hasMedia ? 10 : 0,
                  hasMedia ? 4 : 0,
                ),
                child: _designBubbleText(m, mine: mine),
              ),
            if (sharedUserLink != null)
              Padding(
                padding: EdgeInsets.only(top: hasText ? 8 : 0),
                child: SharedUserProfileMessageCard(
                  userIdentifier: sharedUserLink.userIdentifier,
                  onDarkBackground: mine,
                  onOpenProfile: _openSharedUserProfile,
                ),
              ),
          ],
        ),
      ),
    );

    final column = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (showSenderName)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: GestureDetector(
              key: ValueKey('chat-sender-profile-name-${m.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: !senderIsAdmin && _userForId(m.senderId) != null
                  ? () => _openDirectChatById(m.senderId)
                  : null,
              child: Text(
                senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: figtree(
                  size: 11,
                  weight: FontWeight.w600,
                  color: senderIsAdmin && club != null
                      ? ChatsColors.accentText
                      // A club inbox has exactly two parties, so cycling the
                      // group palette would make one arbitrary colour look
                      // meaningful: both `chats-clubs` 225:5 and
                      // `admin-direct-messages` 335:255 draw this name in
                      // `#71717A`. Groups keep their per-speaker colours.
                      : _isClubInbox
                      ? ChatsColors.muted
                      : chatSenderAccent(senderId),
                ),
              ),
            ),
          ),
        SwipeToReply(
          key: ValueKey('chat-swipe-reply-${m.id}'),
          enabled: chatStore.canWriteThread(widget.threadId, _myId),
          onReply: () => _beginReply(m),
          child: GestureDetector(
            key: ValueKey('chat-message-${m.id}'),
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _openMessageLongPress(m),
            child: bubble,
          ),
        ),
        if (m.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _designReactionChips(m, alignEnd: mine),
          ),
      ],
    );

    return Padding(
      key: anchor,
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (showAvatar)
            Padding(
              // Bottom-aligned beside the bubble, as on `102:152`.
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                key: ValueKey('group-message-avatar-${m.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: _userForId(m.senderId) == null
                    ? null
                    : () => _openDirectChatById(m.senderId),
                child: UserAvatar(
                  userId: senderId,
                  name: senderName,
                  size: 28,
                  fontSize: 11,
                ),
              ),
            ),
          Flexible(child: column),
        ],
      ),
    );
  }

  /// Bubble body text, with search hits picked out in bold when the in-thread
  /// search is open — `search-results` bolds the matched word in place.
  Widget _designBubbleText(ChatMessage m, {required bool mine}) {
    final base = chatBubbleTextStyle(mine: mine);
    final needle = _searchOpen
        ? _searchController.text.trim().toLowerCase()
        : '';
    if (needle.isEmpty) {
      return UserProfileLinkText(
        key: ValueKey('chat-message-text-${m.id}'),
        text: m.content,
        style: base,
        linkStyle: base.copyWith(
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: mine ? ChatsColors.onAccent : ChatsColors.accentText,
          color: mine ? ChatsColors.onAccent : ChatsColors.accentText,
        ),
        onUserLinkTap: _openSharedUserProfile,
      );
    }
    final hit = base.copyWith(fontWeight: FontWeight.w800);
    final spans = <TextSpan>[];
    final lower = m.content.toLowerCase();
    var cursor = 0;
    while (true) {
      final at = lower.indexOf(needle, cursor);
      if (at < 0) break;
      if (at > cursor) {
        spans.add(TextSpan(text: m.content.substring(cursor, at)));
      }
      spans.add(
        TextSpan(text: m.content.substring(at, at + needle.length), style: hit),
      );
      cursor = at + needle.length;
    }
    if (cursor < m.content.length) {
      spans.add(TextSpan(text: m.content.substring(cursor)));
    }
    return Text.rich(
      TextSpan(children: spans),
      key: ValueKey('chat-message-text-${m.id}'),
      style: base,
    );
  }

  Widget _designReplyQuote(
    ChatMessage message, {
    required bool mine,
    required bool hasBody,
  }) {
    final repliedSenderId = message.replyToSenderId ?? '';
    final repliedSenderName = repliedSenderId == _myId
        ? S.you
        : _senderInfo(repliedSenderId).$1;
    final onAccent = mine ? ChatsColors.onAccent : ChatsColors.text;
    return Container(
      key: ValueKey('chat-reply-quote-${message.id}'),
      width: double.infinity,
      margin: EdgeInsets.only(bottom: hasBody ? 7 : 0),
      padding: const EdgeInsets.fromLTRB(10, 7, 9, 7),
      decoration: BoxDecoration(
        color: mine
            ? Colors.black.withValues(alpha: 0.18)
            : ChatsColors.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: mine ? ChatsColors.onAccent : ChatsColors.accent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            repliedSenderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: figtree(
              size: 11,
              weight: FontWeight.w700,
              color: mine ? ChatsColors.onAccent : ChatsColors.accentText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToPreview ?? S.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: figtree(
              size: 11,
              weight: FontWeight.w400,
              color: onAccent.withValues(alpha: 0.82),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _designReactionChips(ChatMessage m, {required bool alignEnd}) {
    final entries = m.reactions.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Wrap(
      spacing: 5,
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      children: [
        for (final entry in entries)
          GestureDetector(
            key: ValueKey('chat-reaction-${m.id}-${entry.key}'),
            onTap: () => chatStore.toggleReaction(
              messageId: m.id,
              userId: _myId,
              emoji: entry.key,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: ChatsColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: entry.value.contains(_myId)
                      ? ChatsColors.accent
                      : ChatsColors.border,
                ),
              ),
              child: Text(
                entry.value.length > 1
                    ? '${entry.key} ${entry.value.length}'
                    : entry.key,
                style: figtree(
                  size: 12,
                  weight: FontWeight.w600,
                  color: ChatsColors.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _designReplyBanner(ChatMessage message) {
    final senderName = message.senderId == _myId
        ? S.you
        : _senderInfo(message.senderId).$1;
    return Container(
      key: const ValueKey('chat-reply-composer-preview'),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: ChatsColors.fill,
        borderRadius: BorderRadius.circular(kChatCardRadius),
        border: Border(left: BorderSide(color: ChatsColors.accent, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.replyingTo(senderName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 11,
                    weight: FontWeight.w700,
                    color: ChatsColors.accentText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.content.trim().isEmpty ? S.message : message.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 12,
                    weight: FontWeight.w400,
                    color: ChatsColors.muted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            key: const ValueKey('chat-cancel-reply'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _replyingTo = null),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: ChatsColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Club rooms get the dedicated community layout (single stream with
    // announcements, polls, events, and the members / notices panels).
    if (_isClub) {
      return ClubCommunityScreen(
        threadId: widget.threadId,
        embedded: widget.embedded,
      );
    }
    if (_designChat) return _buildDesignThread();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _ConversationBackdrop(
              isDark: themeService.isDark,
              accent: AppColors.primaryRed,
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([
              chatStore,
              userState,
              ?_communityInfo,
            ]),
            builder: (context, _) {
              final canAccess = chatStore.canAccessThread(
                widget.threadId,
                _myId,
              );
              if (!canAccess) {
                return SafeArea(
                  bottom: false,
                  child: _buildUnavailableConversation(),
                );
              }
              final messages = chatStore.messagesFor(
                widget.threadId,
                viewerId: _myId,
              );
              // The header takes the status-bar inset itself, so the solid bar
              // runs to the top of the screen rather than leaving a patterned
              // band above it.
              return SafeArea(
                top: false,
                bottom: false,
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(child: _buildMessageList(messages)),
                    _buildInputBar(
                      enabled: chatStore.canWriteThread(widget.threadId, _myId),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Header (back + identity + status, tap for profile peek) ────────────────

  Widget _buildHeader() {
    if (_isGroup) return _buildGroupHeader();
    if (_isClubInbox) return _buildClubInboxHeader();
    final peer = _peer;
    final peerId = ChatStore.dmPeerOf(widget.threadId, _myId);
    final name = peer != null
        ? userState.displayNameFor(peer.id, peer.name)
        : '';
    final academicSummary = userState.academicSummaryFor(peerId ?? '');

    return _headerShell(
      leading: UserAvatar(
        userId: peer?.id ?? peerId ?? '',
        name: peer?.name ?? '',
        size: 38,
        fontSize: 15,
      ),
      title: name,
      // The peer's programme is what the header carries under the name.
      subtitle: Row(
        children: [
          if (academicSummary.isNotEmpty)
            Flexible(
              child: Text(
                academicSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClubInboxHeader() {
    final conversation = _clubInbox;
    final club = _club;
    final showingStudent =
        conversation != null && conversation.profileId != _myId;
    final student = showingStudent ? _userForId(conversation.profileId) : null;
    final title = showingStudent
        ? userState.displayNameFor(conversation.profileId, student?.name ?? '')
        : club?.name ?? '';
    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        (widget.embedded ? 0 : MediaQuery.viewPaddingOf(context).top) + 6,
        12,
        8,
      ),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(
          alpha: themeService.isDark ? 0.94 : 0.97,
        ),
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          if (!widget.embedded) ...[
            IconButton(
              key: const ValueKey('chat-thread-back'),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
              color: AppColors.secondaryText,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey('club-inbox-profile-header'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    if (showingStudent)
                      UserAvatar(
                        userId: conversation.profileId,
                        name: title,
                        size: 40,
                        fontSize: 15,
                      )
                    else if (club != null)
                      ClubAvatar(
                        clubId: club.id,
                        clubName: club.name,
                        color: _colorForClub(club.id),
                        imageUrl: club.logoUrl,
                        size: 40,
                        fontSize: 15,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 12,
                                color: AppColors.primaryRed,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  S.privateSoloChat,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.primaryRed,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            showingStudent ? S.clubInbox : S.privateClubMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lock_rounded, size: 17, color: AppColors.secondaryText),
        ],
      ),
    );
  }

  Widget _buildGroupHeader() {
    final memberIds = chatStore.groupParticipants(widget.threadId);
    final visibleIds = memberIds.where((id) => id != _myId).toList();
    final title = chatStore.groupDisplayName(widget.threadId, _myId);
    return _headerShell(
      tapKey: const ValueKey('group-chat-header'),
      // The stacked avatars bleed ~10% past their own box on both axes, so
      // reserve the extra room instead of letting them crowd the back button
      // and the title, or sit low against the subtitle.
      leading: const SizedBox(width: 43, height: 43),
      leadingOverlay: GroupAvatarStack(
        memberIds: visibleIds,
        nameForUser: (id) => _senderInfo(id).$1,
        photoPath: chatStore.groupForThread(widget.threadId)?.photoUrl,
        size: 38,
      ),
      title: title,
      subtitle: Text(
        S.chatPeopleCount(memberIds.length),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryText,
        ),
      ),
      showChevron: true,
      onTap: _openGroupInfo,
    );
  }

  /// One bar for both thread kinds: back button, identity, optional drill-in
  /// chevron. Keeping the metrics in a single place stops the direct-message
  /// and group headers from drifting apart.
  Widget _headerShell({
    required Widget leading,
    required String title,
    required Widget subtitle,
    Widget? leadingOverlay,
    Key? tapKey,
    bool showChevron = false,
    VoidCallback? onTap,
  }) {
    return Container(
      // A solid bar, so the campus wallpaper stops cleanly at the header edge
      // instead of showing through behind the name.
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        10,
        // viewPadding remains stable even if an ancestor SafeArea has already
        // consumed MediaQuery.padding, keeping the controls below the status
        // bar and Dynamic Island on every pushed chat route.
        (widget.embedded ? 0 : MediaQuery.viewPaddingOf(context).top) + 6,
        12,
        8,
      ),
      child: Row(
        children: [
          if (!widget.embedded) ...[
            // Circular and tinted, rhyming with the composer's buttons — a bare
            // chevron at the screen edge reads as detached.
            Semantics(
              button: true,
              label: MaterialLocalizations.of(context).backButtonTooltip,
              child: GestureDetector(
                key: const ValueKey('chat-thread-back'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.maybePop(context),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 17,
                        color: ChatsColors.backIcon,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: InkWell(
              key: tapKey,
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  children: [
                    if (leadingOverlay == null)
                      leading
                    else
                      Stack(
                        clipBehavior: Clip.none,
                        children: [leading, leadingOverlay],
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.15,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          subtitle,
                        ],
                      ),
                    ),
                    if (showChevron) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: AppColors.secondaryText,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableConversation() {
    return Column(
      key: const ValueKey('chat-unavailable'),
      children: [
        if (!widget.embedded)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                color: AppColors.secondaryText,
              ),
            ),
          ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 44,
                    color: AppColors.secondaryText,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppLocalizations.of(context)!.conversationUnavailableTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    AppLocalizations.of(context)!.conversationUnavailableBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── New-chat intro card ─────────────────────────────────────────────────────

  /// Headline for an empty thread: who you are about to talk to.
  String _introHeadline() {
    if (_isGroup) return chatStore.groupDisplayName(widget.threadId, _myId);
    final peer = _peer;
    final name = peer == null
        ? ''
        : userState.displayNameFor(peer.id, peer.name);
    return name.isEmpty ? S.startConversation : name;
  }

  /// The single quiet line under the name: what you already have in common
  /// with a peer, or who is in a new group. Falls back to plainly naming the
  /// state without adding another instruction to the empty conversation.
  String _introContext() {
    if (_isGroup) {
      final group = chatStore.groupForThread(widget.threadId);
      final count = chatStore.groupParticipants(widget.threadId).length;
      final people = S.chatPeopleCount(count);
      return group?.creatorId == _myId
          ? '$people · ${S.chatCreatedByYou}'
          : people;
    }
    final peer = _peer;
    if (peer == null) return S.chatNoMessagesYet;
    final parts = <String>[];
    final sharedClubId = peer.subscribedClubIds.firstWhere(
      (clubId) => userState.followedClubIds.contains(clubId),
      orElse: () => '',
    );
    final sharedClub = sharedClubId.isEmpty ? null : clubForId(sharedClubId);
    if (sharedClub != null) {
      parts.add(S.chatAlsoIn(_shortClubName(sharedClub)));
    }
    final mutuals = userState.followedUserIds
        .intersection(peer.followingUserIds.toSet())
        .length;
    if (mutuals > 0) parts.add(S.chatMutualFriends(mutuals));
    return parts.isEmpty ? S.chatNoMessagesYet : parts.join(' · ');
  }

  static String _shortClubName(Club club) {
    final shortName = club.shortName?.trim() ?? '';
    if (shortName.isNotEmpty) return shortName;
    final parenthetical = RegExp(r'\(([^)]+)\)').firstMatch(club.name);
    return parenthetical?.group(1) ?? club.name;
  }

  Widget _typingBubble(List<String> actorIds) {
    final visibleActors = actorIds.take(2).toList(growable: false);
    final names = visibleActors
        .map((id) {
          final name = _senderInfo(id).$1.trim();
          return name.isEmpty ? S.studentProfile : name;
        })
        .toList(growable: false);
    final semanticLabel = actorIds.length == 1
        ? S.typingOne(names.first)
        : S.typingMany(names.join(' & '));

    final avatars = <Widget>[];
    if (_isDirect) {
      final peer = _peer;
      final peerId = ChatStore.dmPeerOf(widget.threadId, _myId) ?? '';
      avatars.add(
        UserAvatar(
          userId: peer?.id ?? peerId,
          name: peer?.name ?? _senderInfo(peerId).$1,
          size: 28,
          fontSize: 11,
        ),
      );
    } else if (_isClubInbox) {
      final conversation = _clubInbox;
      final club = _club;
      final showingStudent =
          conversation != null && conversation.profileId != _myId;
      if (showingStudent) {
        final student = _userForId(conversation.profileId);
        avatars.add(
          UserAvatar(
            userId: conversation.profileId,
            name: student?.name ?? _senderInfo(conversation.profileId).$1,
            size: 28,
            fontSize: 11,
          ),
        );
      } else if (club != null) {
        avatars.add(
          ClubAvatar(
            clubId: club.id,
            clubName: club.name,
            color: _colorForClub(club.id),
            imageUrl: club.logoUrl,
            size: 28,
            fontSize: 11,
            shape: 'circle',
          ),
        );
      }
    } else {
      avatars.addAll(
        visibleActors.map(
          (id) => UserAvatar(
            userId: id,
            name: _senderInfo(id).$1,
            size: 28,
            fontSize: 11,
          ),
        ),
      );
    }

    return ChatTypingBubble(
      key: const ValueKey('chat-typing-bubble'),
      avatars: avatars,
      semanticLabel: semanticLabel,
    );
  }

  Widget _buildNewChatIntro() {
    final memberIds = _isGroup
        ? chatStore
              .groupParticipants(widget.threadId)
              .where((id) => id != _myId)
              .toList()
        : const <String>[];
    final peer = _peer;
    final peerId = ChatStore.dmPeerOf(widget.threadId, _myId);
    final context_ = _introContext();

    // No panel, no border, no divider: the backdrop already gives the area
    // texture, so a boxed card here read as a stranded dialog. What is left is
    // who you are talking to, and one quiet line of context.
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            key: const ValueKey('chat-empty-conversation-card'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isGroup)
                // The stack is wider than it is tall, so a circular halo would
                // sit visibly off-centre behind it — the overlap already reads
                // as a deliberate shape on its own.
                GroupAvatarStack(
                  memberIds: memberIds,
                  nameForUser: (id) => _senderInfo(id).$1,
                  photoPath: chatStore
                      .groupForThread(widget.threadId)
                      ?.photoUrl,
                  size: 62,
                )
              else
                // A soft accent halo keeps the avatar from floating unanchored
                // now that the card behind it is gone.
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryRed.withValues(
                      alpha: themeService.isDark ? 0.13 : 0.07,
                    ),
                  ),
                  child: UserAvatar(
                    userId: peer?.id ?? peerId ?? '',
                    name: peer?.name ?? '',
                    size: 72,
                    fontSize: 27,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                _introHeadline(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppColors.text,
                ),
              ),
              if (context_.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  context_,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Message list ────────────────────────────────────────────────────────────

  Widget _buildMessageList(List<ChatMessage> messages) {
    final typing = chatStore.typingUserIds(widget.threadId, excluding: _myId);
    if (messages.isEmpty && typing.isEmpty) return _buildNewChatIntro();

    final items = _buildItems(messages);
    if (typing.isNotEmpty) items.add(_typingBubble(typing));
    final childIndexByKey = <Key, int>{
      for (var i = 0; i < items.length; i++)
        ?items[i].key: items.length - 1 - i,
    };
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      itemCount: items.length,
      findChildIndexCallback: (key) => childIndexByKey[key],
      itemBuilder: (context, i) => items[items.length - 1 - i],
    );
  }

  List<Widget> _buildItems(List<ChatMessage> messages) {
    final items = <Widget>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final prev = i > 0 ? messages[i - 1] : null;
      final next = i < messages.length - 1 ? messages[i + 1] : null;
      final newDay = prev == null || !_sameDay(prev.createdAt, m.createdAt);
      if (newDay) items.add(_DateChip(label: _dayLabel(m.createdAt)));
      final senderId = chatStore.senderIdForViewer(m, _myId);
      final previousSenderId = prev == null
          ? null
          : chatStore.senderIdForViewer(prev, _myId);
      final nextSenderId = next == null
          ? null
          : chatStore.senderIdForViewer(next, _myId);
      final firstOfRun =
          newDay || previousSenderId != senderId || m.replyToMessageId != null;
      final lastOfRun =
          next == null ||
          nextSenderId != senderId ||
          next.replyToMessageId != null ||
          !_sameDay(next.createdAt, m.createdAt);
      items.add(
        SentMessageEntrance(
          key: ValueKey('sent-message-entrance-${m.id}'),
          animate: _animatingSentMessageIds.contains(m.id),
          onCompleted: () => _finishSentMessageEntrance(m.id),
          child: _buildBubbleRow(
            m,
            firstOfRun: firstOfRun,
            lastOfRun: lastOfRun,
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildBubbleRow(
    ChatMessage m, {
    required bool firstOfRun,
    required bool lastOfRun,
  }) {
    final mine = chatStore.isMessageOwner(m, _myId);
    final senderId = chatStore.senderIdForViewer(m, _myId);
    final (senderName, senderIsAdmin) = _senderInfo(senderId);
    final club = _club;
    final isMultiParticipant = _isClub || _isGroup;
    final showHeader = isMultiParticipant && !mine;
    final showClubInboxSenderLabel =
        _isClubInbox && (mine ? _isClubInboxBoardViewer : true);
    final showAvatar = isMultiParticipant;
    final VoidCallback? openSenderChat =
        !mine && !senderIsAdmin && _userForId(m.senderId) != null
        ? () => _openDirectChatById(m.senderId)
        : null;
    final senderAvatar = Container(
      key: _isGroup ? ValueKey('group-message-avatar-${m.id}') : null,
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: AppColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassEdge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 7,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: senderIsAdmin && club != null
          ? ClubAvatar(
              clubId: club.id,
              clubName: club.name,
              color: _colorForClub(club.id),
              imageUrl: club.logoUrl,
              size: 28,
              fontSize: 11,
              shape: 'circle',
            )
          : UserAvatar(
              userId: senderId,
              name: senderName,
              size: 28,
              fontSize: 11,
            ),
    );

    final linkedEventId = m.linkedEventId;
    final hasEventPreview = linkedEventId != null;
    final userLinkMatches = UserProfileLink.matchesIn(m.content);
    final sharedUserLink = userLinkMatches.isEmpty
        ? null
        : userLinkMatches.first;
    final isStandaloneUserLink =
        sharedUserLink != null &&
        UserProfileLink.isStandalone(m.content, sharedUserLink);
    final hasText =
        m.content.trim().isNotEmpty &&
        !hasEventPreview &&
        !isStandaloneUserLink;
    final photoPath = m.kind == ChatMessageKind.photo ? m.attachmentPath : null;
    final attachedFilePath = m.kind == ChatMessageKind.file
        ? m.attachmentPath
        : null;
    final videoPath =
        attachedFilePath != null &&
            isVideoMediaPath(m.attachmentName ?? attachedFilePath)
        ? attachedFilePath
        : null;
    final filePath = videoPath == null ? attachedFilePath : null;
    final hasMedia = photoPath != null || videoPath != null || filePath != null;
    final hasPhoto = photoPath != null;
    final bubbleRadius = hasPhoto ? 16.0 : 20.0;

    final bubble = Container(
      key: ValueKey('chat-message-bubble-${m.id}'),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.76,
      ),
      padding: hasPhoto
          ? const EdgeInsets.all(1)
          : hasMedia
          ? const EdgeInsets.all(5)
          : const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: mine
            ? null
            : AppColors.card.withValues(
                alpha: themeService.isDark ? 0.96 : 0.98,
              ),
        gradient: mine
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryRed, AppColors.darkRed],
              )
            : null,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(bubbleRadius),
          topRight: Radius.circular(bubbleRadius),
          bottomLeft: Radius.circular(mine ? bubbleRadius : 6),
          bottomRight: Radius.circular(mine ? 6 : bubbleRadius),
        ),
        border: hasPhoto
            ? Border.all(
                color: mine ? AppColors.primaryRed : AppColors.glassEdge,
                width: 0.5,
              )
            : mine
            ? null
            : Border.all(color: AppColors.glassEdge),
        boxShadow: hasPhoto
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: mine ? 0.14 : 0.08),
                  blurRadius: 10,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: _messageBodyWithTime(
        message: m,
        mine: mine,
        designChat: false,
        hasPhoto: photoPath != null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.replyToMessageId != null)
              _messageReplyQuote(m, mine: mine, hasMedia: hasMedia),
            if (m.kind == ChatMessageKind.postShare && m.sharedPostId != null)
              SharedPostMessageCard(
                postId: m.sharedPostId!,
                onDarkBackground: mine,
              ),
            if (hasEventPreview)
              SharedEventMessageCard(
                eventId: linkedEventId,
                onDarkBackground: mine,
              ),
            if (photoPath != null)
              _photoAttachmentWithTime(m, mine: mine, designChat: false),
            if (videoPath != null) _videoAttachment(videoPath),
            if (filePath != null) _fileAttachment(m, mine: mine),
            if (hasText)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  hasMedia ? 8 : 0,
                  hasMedia ? 7 : 0,
                  hasMedia ? 8 : 0,
                  hasMedia ? 3 : 0,
                ),
                child: UserProfileLinkText(
                  key: ValueKey('chat-message-text-${m.id}'),
                  text: m.content,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    letterSpacing: -0.1,
                    color: mine ? Colors.white : AppColors.text,
                  ),
                  linkStyle: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    letterSpacing: -0.1,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: mine ? Colors.white : AppColors.primaryRed,
                    color: mine ? Colors.white : AppColors.primaryRed,
                  ),
                  onUserLinkTap: _openSharedUserProfile,
                ),
              ),
            if (sharedUserLink != null)
              Padding(
                padding: EdgeInsets.only(top: hasText ? 8 : 0),
                child: SharedUserProfileMessageCard(
                  userIdentifier: sharedUserLink.userIdentifier,
                  onDarkBackground: mine,
                  onOpenProfile: _openSharedUserProfile,
                ),
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: firstOfRun ? 8 : 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (showAvatar && !mine)
            Padding(
              // Keep the sender identity beside every incoming message.
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: openSenderChat,
                child: senderAvatar,
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showHeader)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: GestureDetector(
                            key: ValueKey('chat-sender-profile-name-${m.id}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: openSenderChat,
                            child: Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                // Each speaker keeps a stable accent so a busy
                                // group stays readable at a glance.
                                color: senderIsAdmin
                                    ? AppColors.primaryRed
                                    : _accentForUser(senderId),
                              ),
                            ),
                          ),
                        ),
                        if (senderIsAdmin) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.lightRed,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              S.adminLabel,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryRed,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                // Swipe left to reply, same as long-press → Reply. Gated on
                // the same write check, so read-only threads stay inert.
                SwipeToReply(
                  key: ValueKey('chat-swipe-reply-${m.id}'),
                  enabled: chatStore.canWriteThread(widget.threadId, _myId),
                  onReply: () => _beginReply(m),
                  child: GestureDetector(
                    key: ValueKey('chat-message-${m.id}'),
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => _openMessageLongPress(m),
                    child: bubble,
                  ),
                ),
                if (m.reactions.isNotEmpty) _reactionChips(m, alignEnd: mine),
                if (showClubInboxSenderLabel)
                  Padding(
                    key: ValueKey('chat-sender-label-${m.id}'),
                    padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                    child: Text(
                      senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showAvatar && mine)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: lastOfRun
                  ? senderAvatar
                  : const SizedBox(width: 32, height: 32),
            ),
        ],
      ),
    );
  }

  // ── Bubble parts ────────────────────────────────────────────────────────────

  static const List<Color> _senderAccents = [
    Color(0xFF00838F),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
  ];

  Color _accentForUser(String userId) {
    if (userId.isEmpty) return AppColors.secondaryText;
    return _senderAccents[userId.hashCode.abs() % _senderAccents.length];
  }

  Widget _messageReplyQuote(
    ChatMessage message, {
    required bool mine,
    required bool hasMedia,
  }) {
    final repliedSenderId = message.replyToSenderId ?? '';
    final repliedSenderName = repliedSenderId == _myId
        ? S.you
        : _senderInfo(repliedSenderId).$1;
    final foreground = mine ? Colors.white : AppColors.text;
    return Container(
      key: ValueKey('chat-reply-quote-${message.id}'),
      width: double.infinity,
      margin: EdgeInsets.only(
        bottom: hasMedia || message.content.isNotEmpty ? 7 : 0,
      ),
      padding: const EdgeInsets.fromLTRB(10, 7, 9, 7),
      decoration: BoxDecoration(
        color: mine
            ? Colors.black.withValues(alpha: 0.16)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: mine ? Colors.white : AppColors.primaryRed,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            repliedSenderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: mine ? Colors.white : AppColors.primaryRed,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToPreview ?? S.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.25,
              color: foreground.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }

  /// Tapping a chip toggles your own reaction; long-pressing the bubble opens
  /// the picker.
  Widget _reactionChips(ChatMessage m, {required bool alignEnd}) {
    final entries = m.reactions.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Wrap(
        spacing: 5,
        alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
        children: [
          for (final entry in entries)
            GestureDetector(
              key: ValueKey('chat-reaction-${m.id}-${entry.key}'),
              onTap: () => chatStore.toggleReaction(
                messageId: m.id,
                userId: _myId,
                emoji: entry.key,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: entry.value.contains(_myId)
                      ? AppColors.lightRed
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: entry.value.contains(_myId)
                        ? AppColors.primaryRed
                        : AppColors.glassEdge,
                  ),
                ),
                child: Text(
                  entry.value.length > 1
                      ? '${entry.key} ${entry.value.length}'
                      : entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// WhatsApp-style message metadata: a quiet footer inside regular bubbles
  /// and a dark, translucent badge over the bottom-right corner of photos.
  Widget _messageTime(
    ChatMessage message, {
    required bool mine,
    required bool designChat,
    bool overPhoto = false,
  }) {
    final foreground = overPhoto
        ? Colors.white.withValues(alpha: 0.92)
        : mine
        ? Colors.white.withValues(alpha: 0.72)
        : designChat
        ? ChatsColors.muted
        : AppColors.secondaryText;
    final metadata = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _timeLabel(message.createdAt),
          style: designChat
              ? figtree(size: 10, weight: FontWeight.w500, color: foreground)
              : TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                ),
        ),
        if (mine && (_isDirect || _isGroup)) ...[
          const SizedBox(width: 4),
          _messageStatusIndicator(
            message,
            compact: true,
            color: foreground,
            seenColor: const Color(0xFF70C8F8),
          ),
        ],
      ],
    );
    return Container(
      key: ValueKey('chat-message-time-${message.id}'),
      padding: overPhoto
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
          : EdgeInsets.zero,
      decoration: overPhoto
          ? BoxDecoration(
              color: Colors.black.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: metadata,
    );
  }

  Widget _messageBodyWithTime({
    required ChatMessage message,
    required bool mine,
    required bool designChat,
    required bool hasPhoto,
    required Widget child,
  }) {
    if (hasPhoto) return child;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 17),
          child: ConstrainedBox(
            // Keeps even a one-character message wide enough for HH:mm plus
            // outgoing delivery ticks without stretching every bubble.
            constraints: const BoxConstraints(minWidth: 54),
            child: child,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: _messageTime(message, mine: mine, designChat: designChat),
        ),
      ],
    );
  }

  Widget _photoAttachmentWithTime(
    ChatMessage message, {
    required bool mine,
    required bool designChat,
  }) {
    return Stack(
      children: [
        _photoAttachment(message),
        Positioned(
          right: 7,
          bottom: 7,
          child: _messageTime(
            message,
            mine: mine,
            designChat: designChat,
            overPhoto: true,
          ),
        ),
      ],
    );
  }

  Widget _photoAttachment(ChatMessage message) {
    final path = message.attachmentPath!;
    final isPrivateReference = path.startsWith('chat-attachment://');
    final isRemote =
        isPrivateReference ||
        path.startsWith('http://') ||
        path.startsWith('https://');
    final file = isRemote ? null : File(path);
    final exists = isRemote || file!.existsSync();
    final ImageProvider? imageProvider = isPrivateReference
        ? null
        : isRemote
        ? CachedNetworkImageProvider(
            path,
            cacheKey: stableSupabaseSignedUrlCacheKey(path),
          )
        : FileImage(file!);
    final sourceAspectRatio = _photoAspectRatioFor(message.id, file);
    final displayAspectRatio = sourceAspectRatio
        .clamp(_chatPortraitPhotoAspectRatio, _chatLandscapePhotoAspectRatio)
        .toDouble();
    return GestureDetector(
      key: ValueKey('chat-photo-${message.id}'),
      onTap: exists
          ? () => _showChatPhoto(
              path: path,
              fallbackProvider: imageProvider,
              isRemote: isRemote,
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: SizedBox(
          width: _chatPhotoWidth,
          child: AspectRatio(
            aspectRatio: displayAspectRatio,
            child: !exists
                ? _missingPhotoPlaceholder()
                : isPrivateReference
                ? PrivateMediaNetworkImage(
                    key: ValueKey('chat-photo-image-${message.id}'),
                    reference: path,
                    rendition: MediaRendition.thumbnail,
                    cacheWidth: 320,
                    fit: BoxFit.cover,
                    onAspectRatio: (ratio) =>
                        _rememberRemotePhotoAspectRatio(message.id, ratio),
                    placeholderBuilder: (_) => _photoLoadingPlaceholder(),
                    errorBuilder: (_) => _missingPhotoPlaceholder(),
                  )
                : isRemote
                ? AppNetworkImage(
                    key: ValueKey('chat-photo-image-${message.id}'),
                    url: path,
                    cacheKey:
                        stableSupabaseSignedUrlCacheKey(path) ??
                        'chat-photo-${message.id}',
                    cacheWidth: 320,
                    fit: BoxFit.cover,
                    preserveSourceAspectRatio: true,
                    onAspectRatio: (ratio) =>
                        _rememberRemotePhotoAspectRatio(message.id, ratio),
                    useOldImageOnUrlChange: true,
                    placeholderBuilder: (_) => _photoLoadingPlaceholder(),
                    errorBuilder: (_) => _missingPhotoPlaceholder(),
                  )
                : Image.file(
                    file!,
                    fit: BoxFit.cover,
                    cacheWidth: (320 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    frameBuilder: (context, child, frame, syncLoaded) =>
                        syncLoaded || frame != null
                        ? child
                        : _photoLoadingPlaceholder(),
                    errorBuilder: (_, _, _) => _missingPhotoPlaceholder(),
                  ),
          ),
        ),
      ),
    );
  }

  double _photoAspectRatioFor(String messageId, File? file) {
    final cached = _photoAspectRatios[messageId];
    if (cached != null) return cached;
    final local = file == null ? null : imageAspectRatioFromFile(file);
    if (local == null) return 4 / 3;
    _photoAspectRatios[messageId] = local;
    return local;
  }

  void _rememberRemotePhotoAspectRatio(String messageId, double aspectRatio) {
    if (!mounted || !aspectRatio.isFinite || aspectRatio <= 0) return;
    final previous = _photoAspectRatios[messageId];
    if (previous != null && (previous - aspectRatio).abs() <= 0.001) return;
    setState(() => _photoAspectRatios[messageId] = aspectRatio);
  }

  Future<void> _showChatPhoto({
    required String path,
    required ImageProvider? fallbackProvider,
    required bool isRemote,
  }) async {
    if (path.startsWith('chat-attachment://')) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        builder: (dialogContext) {
          final size = MediaQuery.sizeOf(dialogContext);
          return GestureDetector(
            onTap: () => Navigator.pop(dialogContext),
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: PrivateMediaNetworkImage(
                  reference: path,
                  rendition: MediaRendition.screen,
                  cacheWidth: size.width,
                  cacheHeight: size.height,
                  fit: BoxFit.contain,
                  placeholderBuilder: (_) => _photoLoadingPlaceholder(),
                  errorBuilder: (_) => _missingPhotoPlaceholder(),
                ),
              ),
            ),
          );
        },
      );
      return;
    }
    var provider = fallbackProvider;
    if (isRemote) {
      try {
        final size = MediaQuery.sizeOf(context);
        final media = await mediaDeliveryService
            .resolvePrivateForCurrentAccount(
              value: path,
              rendition: MediaRendition.screen,
              dimensions: mediaDimensionsFor(
                rendition: MediaRendition.screen,
                logicalWidth: size.width,
                logicalHeight: size.height,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            );
        provider = CachedNetworkImageProvider(
          media.url,
          cacheKey: media.cacheKey,
        );
      } catch (_) {
        // The already-authorized thumbnail remains a safe visual fallback.
      }
    }
    if (!mounted || provider == null) return;
    final resolvedProvider = provider;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.pop(dialogContext),
        child: InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: Image(image: resolvedProvider, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _photoLoadingPlaceholder() => Container(
    alignment: Alignment.center,
    color: AppColors.surfaceAlt,
    child: SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppColors.primaryRed,
      ),
    ),
  );

  Widget _missingPhotoPlaceholder() => Container(
    alignment: Alignment.center,
    color: AppColors.surfaceAlt,
    child: Icon(Icons.image_outlined, size: 26, color: AppColors.secondaryText),
  );

  Widget _videoAttachment(String path) => ClipRRect(
    key: ValueKey('chat-video-$path'),
    borderRadius: BorderRadius.circular(15),
    child: SizedBox(
      width: 220,
      height: 220,
      // Do not open a network video merely to render a conversation row.
      // Playback initialization (and its range requests) begins on tap.
      child: ChatVideoPlayer(path: path, active: false),
    ),
  );

  Widget _fileAttachment(ChatMessage m, {required bool mine}) {
    final name = m.attachmentName ?? S.attachFile;
    final size = _formatFileSize(m.attachmentSize);
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: 0.16)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: mine
              ? Colors.white.withValues(alpha: 0.22)
              : AppColors.glassEdge,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: mine
                  ? Colors.white.withValues(alpha: 0.18)
                  : AppColors.lightRed,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.description_outlined,
              size: 17,
              color: mine ? Colors.white : AppColors.primaryRed,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: mine ? Colors.white : AppColors.text,
                  ),
                ),
                if (size.isNotEmpty)
                  Text(
                    size,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: mine
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Input bar ───────────────────────────────────────────────────────────────

  Widget _buildInputBar({required bool enabled}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card.withValues(
          alpha: themeService.isDark ? 0.96 : 0.98,
        ),
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: SafeArea(
        top: false,
        // Sending a reply drops the quoted preview, and an instant collapse
        // jolts the whole thread up by its height at the same moment the new
        // bubble is arriving. Let the bar close on the same clock instead.
        child: AnimatedSize(
          duration: sentMessageEntranceDuration,
          curve: sentMessageEntranceCurve,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingTo case final replied?) ...[
                _composerReplyPreview(replied),
                const SizedBox(height: 9),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // "+" — photo or camera.
                  _composerCircleButton(
                    key: const ValueKey('chat-attach-button'),
                    size: 40,
                    icon: Icons.add_rounded,
                    iconSize: 21,
                    iconColor: AppColors.primaryRed,
                    onTap: enabled ? _openAttachSheet : null,
                    semanticLabel: S.attachToMessage,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(22),
                        ),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              focusNode: _inputFocusNode,
                              enabled: enabled,
                              minLines: 1,
                              maxLines: 1,
                              textInputAction: TextInputAction.send,
                              textAlignVertical: TextAlignVertical.center,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: enabled ? (_) => _send() : null,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: AppColors.text,
                              ),
                              decoration: InputDecoration(
                                hintText: S.typeMessage,
                                hintStyle: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.secondaryText,
                                ),
                                isDense: true,
                                // The pill already paints the background; avoid
                                // stacking the global field fill on top of it.
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  4,
                                  0,
                                ),
                              ),
                            ),
                          ),
                          // Quick camera capture, docked inside the pill.
                          _composerCircleButton(
                            key: const ValueKey('chat-camera-button'),
                            size: 34,
                            icon: Icons.photo_camera_outlined,
                            iconSize: 19,
                            iconColor: AppColors.secondaryText,
                            filled: false,
                            onTap: enabled
                                ? () => _pickAttachment(_ChatAttachment.camera)
                                : null,
                            semanticLabel: S.takePhoto,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  // Send once there is a draft. The disabled send affordance keeps
                  // the composer layout stable without offering voice notes.
                  ListenableBuilder(
                    listenable: _inputController,
                    builder: (context, _) {
                      final hasDraft =
                          enabled && _inputController.text.trim().isNotEmpty;
                      return AppPressable(
                        key: const ValueKey('chat-send-button'),
                        behavior: HitTestBehavior.opaque,
                        onTap: enabled && hasDraft ? _send : null,
                        pressedScale: 0.92,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: hasDraft ? null : AppColors.surfaceAlt,
                            gradient: hasDraft
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.primaryRed,
                                      AppColors.darkRed,
                                    ],
                                  )
                                : null,
                            shape: BoxShape.circle,
                            border: hasDraft
                                ? null
                                : Border.all(color: AppColors.divider),
                            boxShadow: hasDraft
                                ? [
                                    BoxShadow(
                                      color: AppColors.primaryRed.withValues(
                                        alpha: 0.33,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            Icons.send_rounded,
                            size: 21,
                            color: hasDraft
                                ? Colors.white
                                : AppColors.secondaryText,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composerReplyPreview(ChatMessage message) {
    final senderName = message.senderId == _myId
        ? S.you
        : _senderInfo(message.senderId).$1;
    return Container(
      key: const ValueKey('chat-reply-composer-preview'),
      padding: const EdgeInsets.fromLTRB(11, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppColors.primaryRed, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.replyingTo(senderName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryRed,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ChatStore.replyPreviewFor(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('chat-cancel-reply'),
            tooltip: S.cancelReply,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _replyingTo = null),
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _composerCircleButton({
    required Key key,
    required double size,
    required IconData icon,
    required double iconSize,
    required Color iconColor,
    required VoidCallback? onTap,
    required String semanticLabel,
    bool filled = true,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: AppPressable(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: filled
              ? BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.divider),
                )
              : null,
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      ),
    );
  }

  // ── Time helpers ────────────────────────────────────────────────────────────

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    if (_sameDay(dt, now)) return S.today;
    if (_sameDay(dt, now.subtract(const Duration(days: 1)))) {
      return S.yesterday;
    }
    return '${_months[dt.month - 1]} ${dt.day}';
  }

  String _timeLabel(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _messageStatusIndicator(
    ChatMessage message, {
    bool compact = false,
    Color? color,
    Color? seenColor,
  }) {
    final status = chatStore.deliveryStatusFor(message);
    final ticks = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _MessageTicks(
        key: ValueKey('message-status-${message.id}-${status.name}'),
        status: status,
        color: color,
        seenColor: seenColor,
      ),
    );
    if (!_isGroup) return ticks;

    if (compact) {
      return Semantics(
        button: true,
        label: S.messageInfo,
        child: Tooltip(
          message: S.messageInfo,
          child: GestureDetector(
            key: ValueKey('group-message-receipts-${message.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _openMessageInfo(message),
            child: ticks,
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: S.messageInfo,
      child: Tooltip(
        message: S.messageInfo,
        child: InkResponse(
          key: ValueKey('group-message-receipts-${message.id}'),
          onTap: () => _openMessageInfo(message),
          radius: 22,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(child: ticks),
          ),
        ),
      ),
    );
  }

  String _receiptTimestamp(DateTime value) {
    final dt = value.toLocal();
    final now = DateTime.now();
    final time = _timeLabel(dt);
    if (_sameDay(dt, now)) return time;
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: now.weekday - 1));
    final date = DateTime(dt.year, dt.month, dt.day);
    if (!date.isBefore(startOfWeek) && !date.isAfter(today)) {
      return '${S.weekdayShort(dt.weekday)} $time';
    }
    return '${dt.day.toString().padLeft(2, '0')} ${S.monthShort(dt.month)} $time';
  }
}

/// The design's day marker: a hairline rule on each side of a small caps label.
class _DateChip extends StatelessWidget {
  final String label;

  const _DateChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: AppColors.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: AppColors.divider)),
        ],
      ),
    );
  }
}

/// One check while sent and two once delivered or seen. Bubble metadata may
/// override the colors so the ticks stay legible on accent and photo surfaces.
class _MessageTicks extends StatelessWidget {
  final MessageDeliveryStatus status;
  final Color? color;
  final Color? seenColor;

  const _MessageTicks({
    super.key,
    required this.status,
    this.color,
    this.seenColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: switch (status) {
        MessageDeliveryStatus.sent => S.sent,
        MessageDeliveryStatus.delivered => S.delivered,
        MessageDeliveryStatus.seen => S.seen,
      },
      child: CustomPaint(
        size: const Size(17, 11),
        painter: _TicksPainter(
          color: status == MessageDeliveryStatus.seen
              ? seenColor ?? AppColors.primaryRed
              : color ?? AppColors.secondaryText,
          tickCount: status == MessageDeliveryStatus.sent ? 1 : 2,
        ),
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  final Color color;
  final int tickCount;

  const _TicksPainter({required this.color, required this.tickCount});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 19;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path tick(double dx) => Path()
      ..moveTo((1 + dx) * scale, 6 * scale)
      ..lineTo((4 + dx) * scale, 9 * scale)
      ..lineTo((10 + dx) * scale, 2 * scale);
    canvas.drawPath(tick(0), paint);
    if (tickCount == 2) canvas.drawPath(tick(6.5), paint);
  }

  @override
  bool shouldRepaint(covariant _TicksPainter oldDelegate) =>
      color != oldDelegate.color || tickCount != oldDelegate.tickCount;
}

/// The student thread canvas: a flat body under the design's campus wallpaper
/// and corner bloom.
class _ConversationBackdrop extends StatelessWidget {
  final bool isDark;
  final Color accent;

  const _ConversationBackdrop({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        key: const ValueKey('chat-conversation-backdrop'),
        color: AppColors.background,
        child: ChatCampusBackdrop(isDark: isDark, accent: accent),
      ),
    );
  }
}

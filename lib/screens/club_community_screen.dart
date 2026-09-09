import 'dart:async' show Timer, unawaited;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../models/chat_media_selection.dart';
import '../models/chat_message.dart';
import '../models/club.dart';
import '../models/content_audience.dart';
import '../models/event.dart';
import '../models/user.dart';
import '../navigation/chat_page_route.dart';
import '../services/account_switcher_service.dart';
import '../services/admin_moderation_service.dart';
import '../services/chat_group_prefs.dart';
import '../services/app_colors.dart';
import '../onboarding/tutorial_page_tip.dart';
import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/calendar_rsvp_helper.dart';
import '../services/chat_attachment_staging.dart';
import '../services/chat_store.dart';
import '../services/club_admin_access.dart';
import '../services/club_chat_prefs.dart';
import '../services/content_visibility.dart';
import '../services/club_community_info_controller.dart';
import '../services/locale_service.dart';
import '../services/mock_clubup_profile.dart';
import '../services/mock_data.dart';
import '../services/people_service.dart';
import '../services/rsvp_store.dart';
import '../services/student_club_role_service.dart';
import '../services/theme_service.dart';
import '../services/user_profile_link.dart';
import '../services/user_state.dart';
import '../widgets/chat_campus_backdrop.dart';
import '../widgets/club_avatar.dart';
import '../widgets/chats_design.dart';
import '../widgets/club_board_lane.dart';
import '../widgets/club_chat_design.dart';
import '../widgets/clubup_design.dart';
import '../widgets/content_audience_sheet.dart';
import '../widgets/moderation_reason_sheet.dart';
import '../widgets/club_chat_theme.dart';
import '../widgets/club_community_header.dart';
import '../widgets/club_community_sheet.dart';
import '../widgets/club_composer.dart';
import '../widgets/club_follow_button.dart';
import '../widgets/club_stream_items.dart';
import '../widgets/user_avatar.dart';
import '../widgets/shared_post_message_card.dart';
import '../widgets/sent_message_entrance.dart';
import '../widgets/swipe_to_reply.dart';
import 'chat_camera_screen.dart';
import 'chat_thread_screen.dart';
import 'club_profile_screen.dart';
import 'event_detail_screen.dart';
import 'club_members_screen.dart';
import 'media_preview_screen.dart';
import 'user_profile_screen.dart';

/// The club room, in the Club Board + Chat handoff plus a private Solo Chat
/// surface.
///
/// **Board** is the official notice area and the landing lane: one grouped list,
/// one row per notice, and a composer only for members holding a role in the
/// club. **Chat** is the room — board-member replies, polls, photos and mentions live here,
/// and a notice appears as a card so the conversation around it still reads.
/// **Solo Chat** is the private inbox: one thread for a regular member, or all
/// student-to-club threads for board members and the linked club admin.
///
/// A notice is one object: the record published on the Board is the same message
/// that shows as a card in Chat. Replies never sit under a notice — "Reply in
/// chat" carries it across the lanes as a quote instead.
class ClubCommunityScreen extends StatefulWidget {
  const ClubCommunityScreen({
    super.key,
    required this.threadId,
    this.embedded = false,
    this.initialLane = ClubChatLane.board,
  });

  final String threadId;
  final bool embedded;

  /// Board is where a club room lands; deep links can open Chat directly.
  final ClubChatLane initialLane;

  @override
  State<ClubCommunityScreen> createState() => _ClubCommunityScreenState();
}

class _ClubCommunityScreenState extends State<ClubCommunityScreen>
    with WidgetsBindingObserver {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();

  /// The Board lane's inline composer — `admin-chats-list` 331:136. Kept
  /// apart from [_inputController] so a half-written announcement and a
  /// half-written chat message do not overwrite each other across lanes.
  final _noticeController = TextEditingController();

  /// The Direct lane's inbox filter — `admin-dm-list` 335:36.
  final _directSearchController = TextEditingController();
  String _directQuery = '';

  /// Stable anchors let the pinned banner navigate back to the original item
  /// instead of opening its action sheet.
  final Map<String, GlobalKey> _designMessageAnchors = {};
  final Map<String, GlobalKey> _designNoticeAnchors = {};
  String? _flashingPinnedMessageId;
  Timer? _pinnedFlashTimer;

  /// Which lane the Direct header's chevron returns to.
  ClubCommunityTab _laneBeforeDirect = ClubCommunityTab.board;
  final _scrollController = ScrollController();
  final _unreadDividerKey = GlobalKey();
  final Set<String> _requestedParticipantProfileIds = {};
  final _memberDirectoryRevision = ValueNotifier<int>(0);

  ClubCommunityInfoController? _communityInfo;
  List<User> _memberUsers = const [];
  Future<void>? _memberDirectoryRequest;
  bool _membersLoading = false;
  bool _membersLoadFailed = false;

  /// Frozen on open so the "You left off here" divider does not vanish the
  /// moment the Chat lane is marked read.
  int _unreadAtOpen = 0;
  String? _unreadAnchorMessageId;

  /// Notices that were new when the Board was opened — the row dots survive the
  /// lane being marked read a frame later.
  Set<String> _unreadNoticeIds = const {};

  /// Which room tab is showing. Board is the landing tab.
  late ClubCommunityTab _tab = widget.initialLane == ClubChatLane.board
      ? ClubCommunityTab.board
      : ClubCommunityTab.chat;

  bool _showJumpButton = false;
  ChatTypingSession? _typingSession;
  Set<String> _lastTypingUserIds = const {};
  final Set<String> _animatingSentMessageIds = {};
  ChatMessage? _replyingTo;

  static const List<Color> _clubColors = [
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  String get _myId =>
      authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';

  Club? get _club {
    final clubId = ChatStore.clubIdOf(widget.threadId);
    return clubId == null ? null : clubForId(clubId);
  }

  Color get _accent {
    final club = _club;
    if (club == null) return AppColors.primaryRed;
    final index = clubOrdinal(club.id);
    return _clubColors[(index < 0 ? 0 : index) % _clubColors.length];
  }

  ClubChatTheme get _t => ClubChatTheme.of(_accent);

  bool get _canModerate {
    final club = _club;
    if (club == null) return false;
    final id = _myId;
    if (id.isEmpty) return false;
    return club.adminUserIds.contains(id) ||
        club.boardMemberIds.contains(id) ||
        chatStore.managedCommunityThreadId(id) == widget.threadId;
  }

  /// Only members holding a role in this club get the Board's composer.
  bool get _canPostNotice => chatStore.canPostNotice(widget.threadId, _myId);

  /// Only the club's yönetim kurulu may talk in the Chat lane.
  bool get _canWrite => chatStore.canWriteThread(widget.threadId, _myId);

  /// Backgrounds affect the club's shared community identity, so board
  /// members retain moderation tools without receiving this admin setting.
  bool get _canChangeBackground {
    final club = _club;
    if (club == null || _myId.isEmpty) return false;
    return club.adminUserIds.contains(_myId) ||
        chatStore.managedCommunityThreadId(_myId) == widget.threadId;
  }

  @override
  void initState() {
    super.initState();
    final club = _club;
    if (club != null) {
      _memberUsers = peopleService.reconcileCurrentClubMember(
        fetchedMembers: const [],
        fallbackMembers: clubMembers(club.id),
        currentUser: authService.currentUser,
        currentUserIsFollowing: userState.isFollowing(club.id),
      );
      _communityInfo = ClubCommunityInfoController(
        clubId: club.id,
        fallbackMemberCount: clubMemberCount(club.id),
        fallbackMemberIds: clubMembers(club.id).map((member) => member.id),
      )..addListener(_onCommunityInfoChanged);
    }
    WidgetsBinding.instance.addObserver(this);
    themeService.addListener(_onEnvChanged);
    localeService.addListener(_onEnvChanged);
    clubChatPrefs.addListener(_onEnvChanged);
    chatStore.addListener(_onStoreChanged);
    _inputController.addListener(_onTypingDraftChanged);
    _inputFocusNode.addListener(_onTypingFocusChanged);
    _scrollController.addListener(_onScroll);
    // Post-frame: the community controller and the read receipt both notify
    // listeners, which is illegal while this route is still mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(chatStore.startChatV2Sync(_myId));
      unawaited(chatStore.loadInitialMessagesV2(widget.threadId));
      final canAccess = chatStore.canAccessThread(widget.threadId, _myId);
      if (canAccess || authService.isStudentSession) {
        unawaited(_communityInfo?.start());
        unawaited(_loadMemberDirectory());
      }
      if (!canAccess) return;
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
      _captureUnreadAnchor();
      _hydrateVisibleParticipants();
      _markVisibleMessagesSeen();
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealUnread());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeService.removeListener(_onEnvChanged);
    localeService.removeListener(_onEnvChanged);
    clubChatPrefs.removeListener(_onEnvChanged);
    chatStore.removeListener(_onStoreChanged);
    _inputController.removeListener(_onTypingDraftChanged);
    _inputFocusNode.removeListener(_onTypingFocusChanged);
    _communityInfo?.removeListener(_onCommunityInfoChanged);
    _typingSession?.dispose();
    _communityInfo?.dispose();
    _memberDirectoryRevision.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _noticeController.dispose();
    _directSearchController.dispose();
    _pinnedFlashTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(chatStore.reconcileThreadV2(widget.threadId));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestedParticipantProfileIds.removeWhere(
          (id) => !_hasResolvedProfile(id),
        );
        _hydrateVisibleParticipants();
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

  void _onEnvChanged() {
    if (mounted) setState(() {});
  }

  void _onCommunityInfoChanged() {
    if (mounted) setState(() {});
  }

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
    if (typingAppeared && _tab == ClubCommunityTab.chat) {
      _revealTypingIfNearLatest();
    }
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // reverse:true — offset 0 is the newest message, at the bottom.
    final shouldShow = _scrollController.offset > 80;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <=
        position.viewportDimension * 0.75) {
      unawaited(chatStore.loadOlderMessagesV2(widget.threadId));
    }
    if (shouldShow != _showJumpButton) {
      setState(() => _showJumpButton = shouldShow);
    }
  }

  /// Snapshots what was new in each lane before either is marked read: the
  /// Board's row dots and the Chat lane's "You left off here" divider both need
  /// to survive the read receipt this same open writes.
  void _captureUnreadAnchor() {
    final unreadNotices = chatStore.unreadIdsInClubLane(
      widget.threadId,
      _myId,
      ClubChatLane.board,
    );
    final unreadChat = chatStore.unreadIdsInClubLane(
      widget.threadId,
      _myId,
      ClubChatLane.chat,
    );
    setState(() {
      _unreadNoticeIds = unreadNotices.toSet();
      _unreadAtOpen = unreadChat.length;
      _unreadAnchorMessageId = unreadChat.isEmpty ? null : unreadChat.first;
    });
  }

  void _switchTab(ClubCommunityTab tab) {
    if (_tab == tab) return;
    if (tab != ClubCommunityTab.chat) _typingSession?.stop();
    if (tab == ClubCommunityTab.solo) {
      // `admin-dm-list` 335:6 puts a chevron beside "Messages"; the lane it
      // goes back to is the one the reader left.
      setState(() {
        _laneBeforeDirect = _tab;
        _tab = tab;
        _directSearchController.clear();
        _directQuery = '';
      });
      return;
    }
    final lane = tab == ClubCommunityTab.board
        ? ClubChatLane.board
        : ClubChatLane.chat;
    // Whatever arrived in the other lane while it was hidden is still new to
    // this reader, so it keeps its dot / divider on the way in.
    final incoming = chatStore.unreadIdsInClubLane(
      widget.threadId,
      _myId,
      lane,
    );
    setState(() {
      _tab = tab;
      if (lane == ClubChatLane.board) {
        _unreadNoticeIds = {..._unreadNoticeIds, ...incoming};
      } else if (incoming.isNotEmpty) {
        _unreadAtOpen = incoming.length;
        _unreadAnchorMessageId = incoming.first;
      }
    });
    _markVisibleMessagesSeen();
    if (lane == ClubChatLane.chat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealUnread());
    }
  }

  void _switchLane(ClubChatLane lane) {
    _switchTab(
      lane == ClubChatLane.board
          ? ClubCommunityTab.board
          : ClubCommunityTab.chat,
    );
  }

  /// Brings the "left off here" divider into view when it is close enough to
  /// have been built; otherwise the stream stays pinned to the newest message.
  void _revealUnread() {
    final context = _unreadDividerKey.currentContext;
    if (context == null) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: 0.15,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      ),
    );
  }

  void _markVisibleMessagesSeen() {
    if (!mounted) return;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    // One count per public segment: reading the Board never clears what is
    // waiting in Chat, and the other way round. Solo Chat owns separate inbox
    // threads, whose receipts are handled by ChatThreadScreen.
    if (_tab == ClubCommunityTab.board) {
      chatStore.markClubLaneRead(widget.threadId, _myId, ClubChatLane.board);
    } else if (_tab == ClubCommunityTab.chat) {
      chatStore.markClubLaneRead(widget.threadId, _myId, ClubChatLane.chat);
    }
  }

  void _hydrateVisibleParticipants() {
    if (!chatStore.canAccessThread(widget.threadId, _myId)) return;
    final participantIds =
        <String>{
            ...chatStore
                .messagesFor(widget.threadId, viewerId: _myId)
                .map((message) => message.senderId),
            ...chatStore.typingUserIds(widget.threadId, excluding: _myId),
          }
          ..remove(_myId)
          ..removeAll(_requestedParticipantProfileIds);
    if (participantIds.isEmpty) return;
    _requestedParticipantProfileIds.addAll(participantIds);
    unawaited(
      peopleService.hydrateProfilesByIds(participantIds).then((_) {
        _requestedParticipantProfileIds.removeWhere(
          (id) => !_hasResolvedProfile(id),
        );
        if (mounted) setState(() {});
      }),
    );
  }

  bool _hasResolvedProfile(String userId) {
    return _memberUsers.any((user) => user.id == userId) ||
        peopleService.cachedPeople.any((user) => user.id == userId) ||
        users.any((user) => user.id == userId);
  }

  // ── People ──────────────────────────────────────────────────────────────────

  Future<void> _loadMemberDirectory({bool force = false}) {
    final existing = _memberDirectoryRequest;
    if (existing != null) return existing;

    final club = _club;
    if (club == null) return Future.value();
    if (force) peopleService.invalidateClubMembers(club.id);

    final request = _performMemberDirectoryLoad(club);
    _memberDirectoryRequest = request;
    return request.whenComplete(() {
      if (identical(_memberDirectoryRequest, request)) {
        _memberDirectoryRequest = null;
      }
    });
  }

  Future<void> _performMemberDirectoryLoad(Club club) async {
    if (mounted) {
      setState(() {
        _membersLoading = true;
        _membersLoadFailed = false;
      });
      _memberDirectoryRevision.value++;
    }

    try {
      final fetched = await peopleService.fetchClubMembers(club.id);
      if (!mounted) return;
      setState(() {
        _memberUsers = peopleService.reconcileCurrentClubMember(
          fetchedMembers: fetched,
          fallbackMembers: _memberUsers,
          currentUser: authService.currentUser,
          currentUserIsFollowing: userState.isFollowing(club.id),
        );
        _membersLoading = false;
      });
      _memberDirectoryRevision.value++;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _membersLoading = false;
        _membersLoadFailed = true;
      });
      _memberDirectoryRevision.value++;
    }
  }

  ClubPerson _personFor(String userId) {
    final club = _club;
    // Supabase stores messages sent by a linked club account with the club id
    // in `sender_club_id`. Local optimistic messages may still carry the
    // managed admin id until the remote row is reconciled. Both identities
    // represent the club in this stream, so always render the shared club
    // identity instead of an admin profile.
    if (club != null &&
        (userId == club.id ||
            club.adminUserIds.contains(userId) ||
            managedClubForAdmin(userId)?.id == club.id)) {
      return ClubPerson(
        id: club.id,
        name: club.name,
        role: S.adminLabel,
        isClubAccount: true,
      );
    }
    final adminIndex = clubAdmins.indexWhere((admin) => admin.id == userId);
    if (adminIndex != -1) {
      return ClubPerson(
        id: userId,
        name: clubAdmins[adminIndex].name,
        role: S.adminLabel,
        isClubAccount: true,
      );
    }
    if (userId == appAdmin.id) {
      return ClubPerson(
        id: userId,
        name: appAdmin.name,
        role: S.adminLabel,
        isClubAccount: true,
      );
    }
    final mine = userId == _myId;
    final memberIndex = _memberUsers.indexWhere((user) => user.id == userId);
    final cachedIndex = peopleService.cachedPeople.indexWhere(
      (user) => user.id == userId,
    );
    final knownIndex = users.indexWhere((user) => user.id == userId);
    final knownName = memberIndex != -1
        ? _memberUsers[memberIndex].name
        : (cachedIndex != -1
              ? peopleService.cachedPeople[cachedIndex].name
              : (knownIndex != -1 ? users[knownIndex].name : null));
    final fallbackName = mine
        ? (authService.currentUser?.name ?? S.you)
        : (knownName ?? '');
    return ClubPerson(
      id: userId,
      name: mine ? S.you : userState.displayNameFor(userId, fallbackName),
      role: club == null
          ? null
          : studentClubRoleService.roleTitleFor(club, userId),
    );
  }

  /// Every member of the club, board members first, then A→Z.
  List<ClubPerson> get _members {
    final club = _club;
    if (club == null) return const [];
    final people = <ClubPerson>[];
    final seen = <String>{};
    for (final user in _memberUsers) {
      if (!seen.add(user.id)) continue;
      final mine = user.id == _myId;
      people.add(
        ClubPerson(
          id: user.id,
          name: mine ? S.you : userState.displayNameFor(user.id, user.name),
          role: studentClubRoleService.roleTitleFor(club, user.id),
        ),
      );
    }
    people.sort((a, b) {
      final roleRank = (a.role == null ? 1 : 0).compareTo(
        b.role == null ? 1 : 0,
      );
      if (roleRank != 0) return roleRank;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return people;
  }

  Widget _avatarFor(ClubPerson person, double size) {
    final club = _club;
    if (person.isClubAccount && club != null) {
      return ClubAvatar(
        clubId: club.id,
        clubName: club.name,
        color: _accent,
        imageUrl: club.logoUrl,
        size: size,
        fontSize: size * 0.4,
        shape: 'circle',
      );
    }
    return UserAvatar(
      userId: person.id,
      name: person.name,
      size: size,
      fontSize: size * 0.38,
    );
  }

  // ── Events ──────────────────────────────────────────────────────────────────
  //
  // Events left this surface with the Board + Chat design: the club's Events tab
  // owns them and nothing here can post one. Event cards that a club shared
  // before the change still render, so no history disappears from the room.

  Event? _eventById(String? id) {
    if (id == null) return null;
    final index = events.indexWhere((event) => event.id == id);
    return index == -1 ? null : events[index];
  }

  void _toggleRsvp(Event event) {
    if (!authService.isStudentSession) return;
    unawaited(rsvpStore.toggle(event.id, _myId));
    syncRsvpToDeviceCalendar(context, event);
  }

  void _openEvent(Event event) {
    Navigator.push(
      context,
      ChatPageRoute(
        builder: (_) => EventDetailScreen(event: event, color: _accent),
      ),
    ).then((_) => _markVisibleMessagesSeen());
  }

  // ── Sending ─────────────────────────────────────────────────────────────────

  void _send(String text, List<String> mentions) {
    _typingSession?.stop();
    final sent = chatStore.sendMessage(
      threadId: widget.threadId,
      senderId: _myId,
      content: text,
      mentions: mentions,
      replyToMessageId: _replyingTo?.id,
    );
    if (sent == null) return;
    _inputController.clear();
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

  Future<String?> _ensureClubInboxThread() async {
    final club = _club;
    final profileId = authService.currentUser?.id ?? '';
    if (club == null || profileId.isEmpty) return null;
    return chatStore.ensureClubInboxThread(
      profileId: profileId,
      clubId: club.id,
    );
  }

  Future<void> _messageClubPrivately() async {
    final threadId = await _ensureClubInboxThread();
    if (!mounted) return;
    if (threadId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.secureChatUnavailable)));
      return;
    }
    await Navigator.push(
      context,
      ChatPageRoute(builder: (_) => ChatThreadScreen(threadId: threadId)),
    );
  }

  Future<void> _openSoloChatThread(String threadId) async {
    await Navigator.push(
      context,
      ChatPageRoute(builder: (_) => ChatThreadScreen(threadId: threadId)),
    );
    if (!mounted) return;
    _requestedParticipantProfileIds.removeWhere(
      (id) => !_hasResolvedProfile(id),
    );
    _hydrateVisibleParticipants();
  }

  /// Direct is an inbox for every student-facing private conversation visible
  /// to this viewer. A regular student normally has one row with this club;
  /// board members see every student inquiry for the club.
  void _openDirectSelection() => _switchTab(ClubCommunityTab.solo);

  /// [avatarSize] is 44 everywhere except the board-side inbox, where
  /// `conversation-row` 335:52 draws a 48pt avatar.
  ///
  /// [plainPeerPreview] drops the "Name: " prefix when the last message came
  /// from the student the row is already named after — 335:73 draws the message
  /// alone. Anything from the club's own side keeps its prefix, so the board
  /// can see at a glance which inquiries have been answered.
  List<ClubSoloChatEntry> _soloChatEntries({
    double avatarSize = 44,
    bool plainPeerPreview = false,
  }) {
    final club = _club;
    if (club == null) return const [];
    final entries = <ClubSoloChatEntry>[];
    final summaries = chatStore
        .threadsFor(_myId)
        .where((thread) => thread.isClubInbox && thread.clubId == club.id);
    for (final summary in summaries) {
      final conversation = chatStore.clubInboxForThread(summary.threadId);
      if (conversation == null) continue;
      // A regular member sees only their own club inbox. Board members and
      // the linked club account see every student conversation for this club.
      if (!_canModerate && conversation.profileId != _myId) continue;
      final isOwnConversation = conversation.profileId == _myId;
      final person = isOwnConversation
          ? null
          : _personFor(conversation.profileId);
      final title = isOwnConversation
          ? club.name
          : (person?.name.trim().isNotEmpty == true
                ? person!.name
                : S.studentProfile);
      final last = summary.lastMessage;
      final preview = _soloChatPreview(
        last,
        plainForSenderId: plainPeerPreview ? conversation.profileId : null,
      );
      entries.add(
        ClubSoloChatEntry(
          threadId: summary.threadId,
          title: title,
          preview: preview,
          whenLabel: last == null ? '' : _directRowTime(last.createdAt),
          unread: summary.unread,
          avatar: isOwnConversation
              ? ClubAvatar(
                  clubId: club.id,
                  clubName: club.name,
                  color: _accent,
                  imageUrl: club.logoUrl,
                  size: avatarSize,
                  fontSize: avatarSize * 0.385,
                  shape: 'circle',
                )
              : UserAvatar(
                  userId: conversation.profileId,
                  name: title,
                  size: avatarSize,
                  fontSize: avatarSize * 0.385,
                ),
        ),
      );
    }
    return entries;
  }

  String _soloChatPreview(ChatMessage? message, {String? plainForSenderId}) {
    if (message == null) return S.chatNoMessagesYet;
    final body = switch (message.kind) {
      ChatMessageKind.postShare => S.sharedPost,
      ChatMessageKind.photo => S.attachPhoto,
      ChatMessageKind.file => S.attachFile,
      ChatMessageKind.announcement =>
        (message.title ?? '').trim().isEmpty ? message.content : message.title!,
      _ => message.content,
    };
    final senderId = chatStore.senderIdForViewer(message, _myId);
    if (plainForSenderId != null && senderId == plainForSenderId) return body;
    final sender = senderId == _myId ? S.you : _personFor(senderId).name;
    return sender.trim().isEmpty ? body : '$sender: $body';
  }

  String _directRowTime(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return S.chatsJustNow;
    if (diff.inMinutes < 60) return S.chatsTimeAgo('${diff.inMinutes}m');
    if (diff.inHours < 24) return S.chatsTimeAgo('${diff.inHours}h');
    if (diff.inDays < 7) return S.chatsTimeAgo('${diff.inDays}d');
    return S.chatsTimeAgo('${(diff.inDays / 7).floor()}w');
  }

  void _scrollToLatest() {
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

  Future<void> _handleAttachment(ClubAttachment attachment) async {
    switch (attachment) {
      case ClubAttachment.photo:
        await _pickMediaAttachment(useCamera: false);
      case ClubAttachment.poll:
        await _composePoll();
    }
  }

  /// Opens the in-app camera. The photo comes back upright and, when the front
  /// lens took it, mirrored the way the viewfinder showed it.
  Future<XFile?> _captureWithCamera() => Navigator.of(
    context,
  ).push<XFile>(ChatPageRoute(builder: (_) => const ChatCameraScreen()));

  Future<void> _pickMediaAttachment({
    required bool useCamera,
    bool asAnnouncement = false,
  }) async {
    late final List<XFile> picked;
    try {
      if (useCamera) {
        // The in-app camera, not the system one: iOS's picker always inserts
        // its own Retake/Use Photo step before handing the file back, and this
        // screen already confirms a photo in MediaPreviewScreen. The camera
        // screen also knows which lens fired, so a selfie comes back mirrored
        // to match the viewfinder instead of guessed at from EXIF.
        picked = [?await _captureWithCamera()];
      } else {
        picked = await ImagePicker().pickMultipleMedia(
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 88,
          limit: 30,
        );
      }
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
          initialCaption: asAnnouncement
              ? _noticeController.text.trim()
              : _inputController.text.trim(),
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _sendAttachments(result, asAnnouncement: asAnnouncement);
  }

  Future<void> _sendAttachments(
    MediaPreviewResult result, {
    bool asAnnouncement = false,
  }) async {
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
      final caption = isFirst ? result.caption : '';
      final sent = chatStore.sendMessage(
        threadId: widget.threadId,
        senderId: _myId,
        content: caption,
        kind: asAnnouncement
            ? ChatMessageKind.announcement
            : media.type == ChatMediaType.image
            ? ChatMessageKind.photo
            : ChatMessageKind.file,
        mentions: !asAnnouncement && isFirst
            ? ClubComposer.resolveMentions(caption, _members)
            : const [],
        attachmentPath: stagedPath,
        attachmentName: media.file.name,
        attachmentSize: media.sizeBytes,
        replyToMessageId: !asAnnouncement && isFirst ? _replyingTo?.id : null,
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
    if (asAnnouncement) {
      _noticeController.clear();
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

  Future<void> _composePoll() async {
    var question = '';
    final optionValues = <String>['', ''];
    var closesInHours = 24;
    final t = _t;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: t.sheet,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.borderB,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    S.newPollTitle,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SheetField(
                    hint: S.pollQuestion,
                    t: t,
                    autofocus: true,
                    onChanged: (value) => question = value,
                  ),
                  for (var i = 0; i < optionValues.length; i++) ...[
                    const SizedBox(height: 8),
                    _SheetField(
                      key: ValueKey('club-poll-option-$i'),
                      hint: S.pollOptionLabel(i + 1),
                      t: t,
                      onChanged: (value) => optionValues[i] = value,
                    ),
                  ],
                  if (optionValues.length < 4) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          setSheetState(() => optionValues.add('')),
                      icon: Icon(Icons.add_rounded, size: 18, color: t.red),
                      label: Text(
                        S.addOption,
                        style: TextStyle(
                          color: t.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        S.pollClosesIn,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: t.textMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      for (final option in const [24, 72, 168])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () =>
                                setSheetState(() => closesInHours = option),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: closesInHours == option
                                    ? t.ltRed
                                    : t.solid,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: closesInHours == option
                                      ? t.red
                                      : t.border,
                                ),
                              ),
                              child: Text(
                                option < 48
                                    ? S.pollHours(option)
                                    : S.pollDays(option ~/ 24),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: closesInHours == option
                                      ? t.red
                                      : t.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _PrimaryAction(
                    label: S.post,
                    t: t,
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final normalizedQuestion = question.trim();
    final options = optionValues
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (created != true || normalizedQuestion.isEmpty || options.length < 2) {
      return;
    }

    chatStore.sendMessage(
      threadId: widget.threadId,
      senderId: _myId,
      content: '',
      kind: ChatMessageKind.poll,
      title: normalizedQuestion,
      pollOptions: options,
      pollClosesAt: DateTime.now().add(Duration(hours: closesInHours)),
    );
    _scrollToLatest();
  }

  Future<void> _composeAnnouncement() async {
    var title = '';
    var body = '';
    var pinned = true;
    final t = _t;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          // A Material, not a decorated Container: the sheet holds a
          // `SwitchListTile`, whose ink has nothing to paint on without one
          // ("ListTile background color or ink splashes may be invisible").
          child: Material(
            color: t.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.borderB,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.campaign_outlined, size: 18, color: t.red),
                      const SizedBox(width: 8),
                      Text(
                        S.postAsAnnouncement,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: t.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SheetField(
                    hint: S.announcementTitleHint,
                    t: t,
                    autofocus: true,
                    onChanged: (value) => title = value,
                  ),
                  const SizedBox(height: 8),
                  _SheetField(
                    hint: S.typeMessage,
                    t: t,
                    maxLines: 4,
                    onChanged: (value) => body = value,
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    value: pinned,
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: t.red,
                    title: Text(
                      S.pinToTop,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    onChanged: (value) => setSheetState(() => pinned = value),
                  ),
                  const SizedBox(height: 8),
                  _PrimaryAction(
                    label: S.post,
                    t: t,
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final normalizedTitle = title.trim();
    final normalizedBody = body.trim();
    if (created != true || normalizedTitle.isEmpty) return;

    chatStore.sendMessage(
      threadId: widget.threadId,
      senderId: _myId,
      content: normalizedBody,
      kind: ChatMessageKind.announcement,
      title: normalizedTitle,
      pinned: pinned,
    );
    // One object: the notice is now both the newest row on the Board and a card
    // in Chat. Land the author on the Board, where they published it.
    if (mounted) setState(() => _tab = ClubCommunityTab.board);
  }

  // ── Message actions ─────────────────────────────────────────────────────────

  /// "Reply in chat": switches lanes and carries the message into the composer
  /// as a quote, so the Board never grows a comment thread of its own.
  void _replyInChat(ChatMessage message) {
    if (!_canWrite) return;
    setState(() {
      _replyingTo = message;
      _tab = ClubCommunityTab.chat;
    });
    _markVisibleMessagesSeen();
    _scrollToLatest();
  }

  static const _quickReactions = ['👍', '❤️', '🎉', '👏', '😂', '🙌'];

  Future<void> _confirmDeleteMessage(ChatMessage message) async {
    final t = _t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.sheet,
        title: Text(S.deleteMessage, style: TextStyle(color: t.text)),
        content: Text(S.deleteMessageMsg, style: TextStyle(color: t.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel, style: TextStyle(color: t.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.delete, style: TextStyle(color: t.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      chatStore.deleteMessage(messageId: message.id, userId: _myId);
    }
  }

  void _showMessageActions(ChatMessage message) {
    final t = _t;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: t.sheet,
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
                  color: t.borderB,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final emoji in _quickReactions)
                  GestureDetector(
                    onTap: () {
                      chatStore.toggleReaction(
                        messageId: message.id,
                        userId: _myId,
                        emoji: emoji,
                      );
                      Navigator.of(sheetContext).pop();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            message.reactions[emoji]?.contains(_myId) ?? false
                            ? t.ltRed
                            : t.solid,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.border),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_canWrite)
              _ActionRow(
                key: ValueKey('club-reply-message-${message.id}'),
                icon: Icons.reply_rounded,
                label: message.kind == ChatMessageKind.announcement
                    ? S.boardReplyInChat
                    : S.reply,
                t: t,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _replyInChat(message);
                },
              ),
            if (message.content.isNotEmpty)
              _ActionRow(
                icon: Icons.copy_rounded,
                label: S.copyText,
                t: t,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  Navigator.of(sheetContext).pop();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(S.copied)));
                },
              ),
            if (chatStore.isMessageOwner(message, _myId))
              _ActionRow(
                key: ValueKey('club-delete-message-${message.id}'),
                icon: Icons.delete_outline_rounded,
                label: S.deleteMessage,
                t: t,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_confirmDeleteMessage(message));
                },
              ),
            if (_canModerate)
              _ActionRow(
                icon: message.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: message.pinned ? S.unpin : S.pinToTop,
                t: t,
                onTap: () {
                  chatStore.setPinned(message.id, !message.pinned);
                  Navigator.of(sheetContext).pop();
                },
              ),
            _ActionRow(
              icon: Icons.person_outline_rounded,
              label: S.viewProfile,
              t: t,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openProfile(message.senderId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openProfile(String userId) {
    final currentUser = authService.currentUser;
    User? user = currentUser?.id == userId ? currentUser : null;
    final memberIndex = _memberUsers.indexWhere(
      (person) => person.id == userId,
    );
    if (user == null && memberIndex != -1) user = _memberUsers[memberIndex];
    final cachedIndex = peopleService.cachedPeople.indexWhere(
      (person) => person.id == userId,
    );
    if (user == null && cachedIndex != -1) {
      user = peopleService.cachedPeople[cachedIndex];
    }
    final knownIndex = users.indexWhere((person) => person.id == userId);
    if (user == null && knownIndex != -1) user = users[knownIndex];
    if (user == null) return;
    Navigator.push(
      context,
      ChatPageRoute(builder: (_) => UserProfileScreen(user: user!)),
    ).then((_) => _markVisibleMessagesSeen());
  }

  Future<void> _openSharedUserProfile(String userIdentifier) async {
    final user = await resolveUserProfileLink(userIdentifier);
    if (!mounted || user == null) return;
    await Navigator.push(
      context,
      ChatPageRoute<void>(builder: (_) => UserProfileScreen(user: user)),
    );
    if (mounted) _markVisibleMessagesSeen();
  }

  void _openParticipantProfile(ClubPerson person) {
    if (person.isClubAccount) {
      _openClubProfile();
      return;
    }
    _openProfile(person.id);
  }

  void _openClubProfile() {
    final club = _club;
    if (club == null) return;
    Navigator.push(
      context,
      ChatPageRoute(
        builder: (_) => ClubProfileScreen(club: club, color: _accent),
      ),
    ).then((_) => _markVisibleMessagesSeen());
  }

  void _openSettingsSheet() {
    final t = _t;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: t.sheet,
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
                  color: t.borderB,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Members and About moved behind this menu with the Board + Chat
            // design — the segments own navigation now.
            _ActionRow(
              key: const ValueKey('club-open-members'),
              icon: Icons.people_outline_rounded,
              label: S.communityMembersButton,
              t: t,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openMembersSheet();
              },
            ),
            _ActionRow(
              icon: Icons.groups_2_outlined,
              label: S.openClubProfile,
              t: t,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openClubProfile();
              },
            ),
            if (_canPostNotice)
              _ActionRow(
                icon: Icons.campaign_outlined,
                label: S.boardPostNotice,
                t: t,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_composeAnnouncement());
                },
              ),
            if (_canChangeBackground)
              _ActionRow(
                icon: Icons.wallpaper_rounded,
                label: S.changeChatBackground,
                t: t,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openBackgroundSheet();
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Sheets ──────────────────────────────────────────────────────────────────

  String _backgroundLabel(ClubChatBackground background) =>
      switch (background) {
        ClubChatBackground.classic => S.backgroundClassic,
        ClubChatBackground.warm => S.backgroundWarm,
        ClubChatBackground.ocean => S.backgroundOcean,
        ClubChatBackground.forest => S.backgroundForest,
        ClubChatBackground.midnight => S.backgroundMidnight,
      };

  LinearGradient _backgroundGradient(
    ClubChatBackground background,
    ClubChatTheme t,
  ) {
    final colors = switch (background) {
      ClubChatBackground.classic => [
        t.body,
        Color.lerp(t.body, t.accent, t.isDark ? 0.10 : 0.055)!,
      ],
      ClubChatBackground.warm =>
        t.isDark
            ? const [Color(0xFF241A18), Color(0xFF321D22)]
            : const [Color(0xFFFFF8F0), Color(0xFFFDE9E8)],
      ClubChatBackground.ocean =>
        t.isDark
            ? const [Color(0xFF111D2B), Color(0xFF132C38)]
            : const [Color(0xFFF2F8FF), Color(0xFFE5F3F8)],
      ClubChatBackground.forest =>
        t.isDark
            ? const [Color(0xFF13221C), Color(0xFF1D2D24)]
            : const [Color(0xFFF2FAF5), Color(0xFFE5F3E9)],
      ClubChatBackground.midnight =>
        t.isDark
            ? const [Color(0xFF0B1020), Color(0xFF1B1730)]
            : const [Color(0xFFF0F2FC), Color(0xFFE8E6F7)],
    };
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }

  void _openBackgroundSheet() {
    if (!_canChangeBackground) return;
    final t = _t;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: BoxDecoration(
            color: t.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.borderB,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  S.chatBackground,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final optionWidth = (constraints.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final background in ClubChatBackground.values)
                          SizedBox(
                            width: optionWidth,
                            child: _backgroundOption(
                              background,
                              t,
                              selected:
                                  clubChatPrefs.backgroundFor(
                                    widget.threadId,
                                  ) ==
                                  background,
                              onTap: () {
                                clubChatPrefs.setBackground(
                                  widget.threadId,
                                  background,
                                );
                                setSheetState(() {});
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: t.red,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(S.done),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backgroundOption(
    ClubChatBackground background,
    ClubChatTheme t, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: _backgroundLabel(background),
      child: GestureDetector(
        key: ValueKey('club-background-option-${background.name}'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: selected ? t.ltRed : t.solid,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? t.red : t.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: _backgroundGradient(background, t),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.chat_rounded,
                  size: 20,
                  color: selected ? t.red : t.sub,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _backgroundLabel(background),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMembersSheet() {
    unawaited(_loadMemberDirectory(force: _membersLoadFailed));
    final t = _t;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ListenableBuilder(
        listenable: Listenable.merge([
          chatStore,
          userState,
          _memberDirectoryRevision,
        ]),
        builder: (sheetContext, _) => ClubCommunitySheet(
          t: t,
          title: S.communityMembersButton,
          builder: (context) => _membersPanel(t),
        ),
      ),
    );
  }

  Widget _membersPanel(ClubChatTheme t) {
    final people = _members;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_membersLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: t.red,
              backgroundColor: t.border,
            ),
          ),
        if (_membersLoadFailed && people.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 4),
            child: Center(
              child: TextButton.icon(
                onPressed: () => unawaited(_loadMemberDirectory(force: true)),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(S.retryMembers),
                style: TextButton.styleFrom(foregroundColor: t.red),
              ),
            ),
          ),
        ClubSheetLabel(label: S.chatMembers(people.length), t: t),
        for (final person in people) _memberRow(person, t),
      ],
    );
  }

  Widget _memberRow(ClubPerson person, ClubChatTheme t) {
    return Padding(
      key: ValueKey('club-member-row-${person.id}'),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          _avatarFor(person, 38),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ClubRoleChip(
                      person: person,
                      t: t,
                      show: clubChatPrefs.showRoles,
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              _openProfile(person.id);
            },
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.solid,
                shape: BoxShape.circle,
                border: Border.all(color: t.border),
              ),
              child: Icon(Icons.edit_outlined, size: 15, color: t.red),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  Widget _clubComposerReplyPreview(ChatMessage message, ClubChatTheme t) {
    // A quoted notice keeps its own treatment: "Reply in chat" is a lane jump,
    // so the composer says which notice this message is answering.
    if (message.kind == ChatMessageKind.announcement) {
      return ClubNoticeQuoteBar(
        title: (message.title ?? '').trim().isEmpty
            ? message.content
            : message.title!,
        t: t,
        onClear: () => setState(() => _replyingTo = null),
      );
    }
    final sender = _personFor(message.senderId).name;
    return Container(
      key: const ValueKey('club-reply-composer-preview'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: t.body,
        border: Border(
          top: BorderSide(color: t.hair),
          left: BorderSide(color: t.red, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.replyingTo(sender),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: t.red,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ChatStore.replyPreviewFor(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.sub),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('club-cancel-reply'),
            tooltip: S.cancelReply,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _replyingTo = null),
            icon: Icon(Icons.close_rounded, size: 18, color: t.sub),
          ),
        ],
      ),
    );
  }

  // ── CLUB CHATS INSIDE: the student club room ────────────────────────────────
  // `club-announcements` 143:188 (Board), `club-chat-reply` 143:3 (Chats),
  // `club-detail-dropdown` 219:6 (the lane menu) and the two sheets at
  // `146:3` / `146:298`. Direct routes out to the club-inbox thread, which is
  // `chats-clubs` 225:5 and already drawn by ChatThreadScreen.
  //
  // The `CLUB CHATS` section (label `543:32`) then drew the same room from the
  // club's side — `admin-chats-list` 331:136 (Board), `admin-board-chat` 331:10
  // (Chats), `admin-dm-list` 335:6 (Direct) — so a club login takes this path
  // too, including the room embedded in its Chats tab. The ClubUp platform
  // moderator is the one session left on the previous chrome (the segmented
  // lane switch, the campus wallpaper, the club-themed accents): no frame has
  // been drawn for it.

  /// A club account reading its own room. Two shapes count, the same pair
  /// CLUB HOME branches on: a dedicated club login, and a student who has
  /// switched to the linked club account **for this club**. The ClubUp
  /// platform moderator does not — it administers every club and has no room
  /// of its own.
  bool get _isClubSideSession {
    final admin = authService.currentAdmin;
    if (admin != null) return !isClubUpAdmin(admin);
    final active = accountSwitcherService.activeClub;
    return active != null && active.id == _club?.id;
  }

  bool get _designClubRoom =>
      _isClubSideSession || (authService.isStudentSession && !widget.embedded);

  final GlobalKey _laneAnchorKey = GlobalKey();

  ClubRoomLane get _designLane => switch (_tab) {
    ClubCommunityTab.board => ClubRoomLane.board,
    ClubCommunityTab.chat => ClubRoomLane.chats,
    ClubCommunityTab.solo => ClubRoomLane.direct,
  };

  Future<void> _openLaneMenu() async {
    final selected = await showClubLaneMenu(
      context: context,
      anchorKey: _laneAnchorKey,
      current: _designLane,
      badges: {
        ClubRoomLane.board: _laneUnread(ClubChatLane.board),
        ClubRoomLane.chats: _laneUnread(ClubChatLane.chat),
        ClubRoomLane.direct: _soloChatEntries().fold<int>(
          0,
          (total, entry) => total + entry.unread,
        ),
      },
    );
    if (selected == null || !mounted) return;
    switch (selected) {
      case ClubRoomLane.board:
        _switchTab(ClubCommunityTab.board);
      case ClubRoomLane.chats:
        _switchTab(ClubCommunityTab.chat);
      case ClubRoomLane.direct:
        _openDirectSelection();
    }
  }

  /// `UserAvatar` falls back to an **infinite** shimmer when it is handed an
  /// empty name (`user_avatar.dart:118`), and a club stream can carry a sender
  /// whose profile never resolved. Give those a readable placeholder instead —
  /// otherwise the room shimmers for good and `pumpAndSettle` never returns.
  ClubPerson _designPerson(ClubPerson person) => person.name.trim().isNotEmpty
      ? person
      : ClubPerson(
          id: person.id,
          name: S.studentProfile,
          role: person.role,
          isClubAccount: person.isClubAccount,
        );

  Widget _designAvatar(ClubPerson person, double size) =>
      _avatarFor(_designPerson(person), size);

  /// `admin-dm-list` 335:6 turns the Direct lane into an inbox: a "Messages"
  /// title where the other two lanes name the club, and a search field.
  ///
  /// Club side only. A student board member also sees every student's thread,
  /// but their lane was drawn by CLUB CHATS INSIDE and approved as it is —
  /// this section only reviewed the club's own view of it.
  bool get _designDirectInbox =>
      _tab == ClubCommunityTab.solo && _isClubSideSession;

  Widget _buildDesignRoom(Club club) {
    final memberCount =
        supabaseClubMemberCounts[club.id] ??
        _communityInfo?.memberCount ??
        clubMemberCount(club.id);
    if (_designDirectInbox) {
      return Column(
        children: [
          ClubDirectInboxHeader(
            title: S.clubDirectInboxTitle,
            laneAnchorKey: _laneAnchorKey,
            onLaneTap: () => unawaited(_openLaneMenu()),
            onBack: () => _switchTab(_laneBeforeDirect),
          ),
          ClubDirectSearchField(
            controller: _directSearchController,
            hint: S.chatsSearchMessages,
            onChanged: (value) => setState(() => _directQuery = value),
          ),
          Expanded(child: _buildDesignDirectInbox()),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              ClubRoomHeader(
                avatar: ClubAvatar(
                  clubId: club.id,
                  clubName: club.name,
                  color: _accent,
                  imageUrl: club.logoUrl,
                  size: 38,
                  fontSize: 15,
                  shape: 'circle',
                ),
                clubName: club.name,
                memberLine: S.clubMembersAndUnread(memberCount, 0),
                lane: _designLane,
                laneAnchorKey: _laneAnchorKey,
                onLaneTap: () => unawaited(_openLaneMenu()),
                onBack: widget.embedded
                    ? null
                    : () => Navigator.maybePop(context),
                onOpenClub: _openDesignMembers,
              ),
              Expanded(
                child: switch (_tab) {
                  ClubCommunityTab.board => _buildDesignBoardLane(),
                  ClubCommunityTab.chat => _buildDesignChatLane(),
                  ClubCommunityTab.solo => _buildDesignDirectLane(),
                },
              ),
            ],
          ),
        ),
        // `tut-announcements` 389:2162 — a page-level tip rather than a tour
        // stop, so it fires the first time a student opens the Board lane
        // whether or not they took the tour.
        Positioned.fill(child: _buildAnnouncementsTip()),
      ],
    );
  }

  /// The Board lane's one-off coach mark, spotlighting the first notice.
  Widget _buildAnnouncementsTip() {
    final notices = chatStore.noticesIn(widget.threadId);
    final active =
        _tab == ClubCommunityTab.board &&
        authService.isStudentSession &&
        !_isClubSideSession &&
        notices.isNotEmpty;
    return TutorialPageTipOverlay(
      tipId: TutorialPageTips.announcements,
      anchorKey: active ? _designNoticeAnchors[notices.first.id] : null,
      pageLabel: () => S.tutorialPageAnnouncements,
      title: () => S.tutorialAnnouncementsTitle,
      body: () => S.tutorialAnnouncementsBody,
      active: active,
    );
  }

  void _openDesignMembers() {
    final club = _club;
    if (club == null) return;
    Navigator.push(
      context,
      ChatPageRoute(
        builder: (_) => ClubMembersScreen(club: club, myId: _myId),
      ),
    );
  }

  // ── Board lane ─────────────────────────────────────────────────────────────

  /// `club-announcements` 143:215 — one card per notice, pinned first, and the
  /// locked footer when the reader cannot post one.
  Widget _buildDesignBoardLane() {
    final notices = chatStore.noticesIn(widget.threadId);
    return Column(
      children: [
        Expanded(
          child: notices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      S.boardEmptyTitle,
                      textAlign: TextAlign.center,
                      style: figtree(
                        size: 14,
                        weight: FontWeight.w500,
                        color: ChatsColors.muted,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: notices.length,
                  itemBuilder: (context, index) {
                    final notice = notices[index];
                    final person = _designPerson(
                      _personFor(chatStore.senderIdForViewer(notice, _myId)),
                    );
                    final title = (notice.title ?? '').trim();
                    final body = notice.content.trim();
                    return KeyedSubtree(
                      key: _designNoticeAnchors.putIfAbsent(
                        notice.id,
                        GlobalKey.new,
                      ),
                      child: ClubNoticeCard(
                        key: ValueKey('club-notice-card-${notice.id}'),
                        avatar: _designAvatar(person, 28),
                        authorName: person.name,
                        roleLabel: person.role,
                        whenLabel: _designNoticeWhen(notice.createdAt),
                        title: title.isEmpty || title == body ? null : title,
                        body: body,
                        attachment: _designNoticeAttachment(notice),
                        pinned: notice.pinned,
                        reactions: {
                          for (final entry in notice.reactions.entries)
                            entry.key: entry.value.length,
                        },
                        myReactions: {
                          for (final entry in notice.reactions.entries)
                            if (entry.value.contains(_myId)) entry.key,
                        },
                        replyCount: chatStore.replyCountFor(notice.id),
                        onToggleReaction: _canWrite
                            ? (emoji) => chatStore.toggleReaction(
                                messageId: notice.id,
                                userId: _myId,
                                emoji: emoji,
                              )
                            : null,
                        onLongPress: () => _showDesignMessageActions(notice),
                        onOpenReplies: () => _replyInChat(notice),
                      ),
                    );
                  },
                ),
        ),
        if (!_canPostNotice)
          ClubLockedStrip(label: S.clubOnlyAdminsPost)
        else
          _buildDesignNoticeComposerStrip(),
      ],
    );
  }

  Widget? _designNoticeAttachment(ChatMessage notice) {
    final path = notice.attachmentPath?.trim() ?? '';
    if (path.isEmpty) return null;
    final name = notice.attachmentName ?? path;
    final Widget attachment = isVideoMediaPath(name)
        ? ClubVideoAttachment(path: path, t: _t)
        : isImageMediaPath(name)
        ? ClubPhotoAttachment(path: path, t: _t)
        : ClubFileChip(
            message: notice,
            t: _t,
            onOpen: () => _showDesignMessageActions(notice),
          );
    return KeyedSubtree(
      key: ValueKey('club-notice-attachment-${notice.id}'),
      child: attachment,
    );
  }

  /// `admin-chats-list` 331:136 — "Write an announcement…" with a paperclip and
  /// the accent send button, in place of the primary button the student pass
  /// invented for this footer (the student frame draws only the locked strip,
  /// since it is a plain member's view).
  ///
  /// On the club side the paperclip follows the same media flow as Chats:
  /// library or live camera, then preview/caption. The details tile preserves
  /// the existing headline-and-pin editor. Student board members retain their
  /// established attachment behavior.
  Widget _buildDesignNoticeComposerStrip() {
    return ChatComposerBar(
      key: const ValueKey('club-design-notice-composer'),
      controller: _noticeController,
      enabled: true,
      hint: S.clubBoardComposerHint,
      onAttach: () => unawaited(
        _isClubSideSession
            ? _openAnnouncementAttachSheet()
            : _composeAnnouncement(),
      ),
      onSend: _sendInlineNotice,
    );
  }

  Future<void> _openAnnouncementAttachSheet() async {
    final club = _club;
    if (club == null) return;
    final memberCount =
        supabaseClubMemberCounts[club.id] ??
        _communityInfo?.memberCount ??
        clubMemberCount(club.id);
    await showClubShareSheet(
      context,
      clubName: club.name,
      visibilityLine: S.clubShareVisibility(memberCount),
      options: [
        ClubShareOption(
          tileKey: const ValueKey('club-announcement-share-media'),
          icon: Icons.photo_library_outlined,
          label: S.attachMedia,
          onTap: () => unawaited(
            _pickMediaAttachment(useCamera: false, asAnnouncement: true),
          ),
        ),
        ClubShareOption(
          tileKey: const ValueKey('club-announcement-share-camera'),
          icon: Icons.photo_camera_outlined,
          label: S.takePhoto,
          onTap: () => unawaited(
            _pickMediaAttachment(useCamera: true, asAnnouncement: true),
          ),
        ),
        ClubShareOption(
          tileKey: const ValueKey('club-announcement-details'),
          icon: Icons.campaign_outlined,
          label: S.postAsAnnouncement,
          onTap: () => unawaited(_composeAnnouncement()),
        ),
      ],
    );
  }

  /// A notice with no headline of its own: `title` and `content` carry the same
  /// text, which is what [ClubNoticeCard] draws as a plain card — exactly the
  /// cards on 331:136, none of which has a bold headline.
  void _sendInlineNotice() {
    final body = _noticeController.text.trim();
    if (body.isEmpty) return;
    chatStore.sendMessage(
      threadId: widget.threadId,
      senderId: _myId,
      content: body,
      kind: ChatMessageKind.announcement,
      title: body,
      pinned: false,
    );
    _noticeController.clear();
  }

  /// `143:230` — "Monday · 09:12": the weekday inside the last week, a date
  /// before that, then the clock.
  String _designNoticeWhen(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    final clock = _timeLabel(value);
    if (diff.inDays == 0) return '${S.today} · $clock';
    if (diff.inDays == 1) return '${S.yesterday} · $clock';
    if (diff.inDays < 7) {
      return '${DateFormat.EEEE(localeService.languageCode).format(value)} · $clock';
    }
    return '${DateFormat.MMMd(localeService.languageCode).format(value)} · $clock';
  }

  // ── Chats lane ─────────────────────────────────────────────────────────────

  Widget _typingBubble(List<ClubPerson> people, {bool design = false}) {
    final visible = people.take(2).map(_designPerson).toList(growable: false);
    final label = people.length == 1
        ? S.typingOne(_firstName(visible.first.name))
        : S.typingMany(visible.map((p) => _firstName(p.name)).join(' & '));
    return ChatTypingBubble(
      key: const ValueKey('club-typing-row'),
      avatars: [
        for (final person in visible)
          design ? _designAvatar(person, 28) : _avatarFor(person, 28),
      ],
      semanticLabel: label,
    );
  }

  /// `club-chat-reply` 143:30 — the group-thread language from the CHATS area
  /// plus what only a club room has: announcement cards, a pinned strip, a
  /// seen count and typing.
  Widget _buildDesignChatLane() {
    final messages = chatStore
        .messagesFor(widget.threadId, viewerId: _myId)
        .toList();
    final typing = chatStore
        .typingUserIds(widget.threadId, excluding: _myId)
        .map(_personFor)
        .toList();
    final pinned = chatStore.pinnedMessageIn(widget.threadId);

    final items = <Widget>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final previous = i == 0 ? null : messages[i - 1];
      final next = i == messages.length - 1 ? null : messages[i + 1];
      if (previous == null ||
          !_sameDesignDay(previous.createdAt, message.createdAt)) {
        items.add(ChatDayDivider(label: _designDayLabel(message.createdAt)));
      }
      if (message.kind == ChatMessageKind.announcement) {
        items.add(_buildDesignChatAnnouncement(message));
        continue;
      }
      final senderId = chatStore.senderIdForViewer(message, _myId);
      final nextSenderId = next == null
          ? null
          : chatStore.senderIdForViewer(next, _myId);
      final lastOfRun =
          next == null ||
          next.kind == ChatMessageKind.announcement ||
          nextSenderId != senderId ||
          !_sameDesignDay(next.createdAt, message.createdAt);
      items.add(
        SentMessageEntrance(
          key: ValueKey('sent-message-entrance-${message.id}'),
          animate: _animatingSentMessageIds.contains(message.id),
          onCompleted: () => _finishSentMessageEntrance(message.id),
          child: _buildDesignClubBubble(message, showTail: lastOfRun),
        ),
      );
    }
    if (typing.isNotEmpty) {
      items.add(_typingBubble(typing, design: true));
    }
    final childIndexByKey = <Key, int>{
      for (var i = 0; i < items.length; i++)
        ?items[i].key: items.length - 1 - i,
    };

    return Column(
      children: [
        Expanded(
          child: Stack(
            key: const ValueKey('club-chat-history-stack'),
            children: [
              Positioned.fill(
                child: messages.isEmpty && typing.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            S.clubChatEmptyLine,
                            textAlign: TextAlign.center,
                            style: figtree(
                              size: 14,
                              weight: FontWeight.w500,
                              color: ChatsColors.muted,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: items.length,
                        findChildIndexCallback: (key) => childIndexByKey[key],
                        itemBuilder: (context, i) =>
                            items[items.length - 1 - i],
                      ),
              ),
              if (pinned != null)
                Positioned(
                  top: 0,
                  left: 16,
                  right: 16,
                  child: ClubSystemStrip(
                    key: const ValueKey('club-pinned-strip'),
                    icon: Icons.bookmark_rounded,
                    label: S.clubPinnedByLine(
                      _designPerson(
                        _personFor(chatStore.senderIdForViewer(pinned, _myId)),
                      ).name,
                    ),
                    onTap: () => unawaited(_jumpToPinnedItem(pinned, messages)),
                  ),
                ),
            ],
          ),
        ),
        if (_canWrite)
          ChatComposerBar(
            controller: _inputController,
            focusNode: _inputFocusNode,
            enabled: true,
            hint: S.communityComposerHint,
            onAttach: () => unawaited(_openDesignShareSheet()),
            onSend: () => _send(_inputController.text, const []),
            banner: _replyingTo == null
                ? null
                : _buildDesignReplyBanner(_replyingTo!),
          )
        else
          ClubLockedStrip(label: S.clubChannelReadOnly),
      ],
    );
  }

  Future<void> _jumpToPinnedItem(
    ChatMessage pinned,
    List<ChatMessage> chatMessages,
  ) async {
    final targetContext = _designMessageAnchors[pinned.id]?.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.3,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      if (mounted) _startPinnedMessageFlash(pinned.id);
      return;
    }
    if (!_scrollController.hasClients) return;

    final messageIndex = chatMessages.indexWhere(
      (message) => message.id == pinned.id,
    );
    if (messageIndex == -1) return;
    final distanceFromNewest = chatMessages.length - 1 - messageIndex;
    final fraction = chatMessages.length <= 1
        ? 0.0
        : distanceFromNewest / (chatMessages.length - 1);
    final estimatedOffset =
        _scrollController.position.maxScrollExtent * fraction;
    await _scrollController.animateTo(
      estimatedOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final resolvedContext = _designMessageAnchors[pinned.id]?.currentContext;
    if (resolvedContext != null && resolvedContext.mounted) {
      await Scrollable.ensureVisible(
        resolvedContext,
        alignment: 0.3,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      if (mounted) _startPinnedMessageFlash(pinned.id);
    }
  }

  void _startPinnedMessageFlash(String messageId) {
    _pinnedFlashTimer?.cancel();
    if (!mounted) return;

    void activate() {
      if (!mounted) return;
      setState(() => _flashingPinnedMessageId = messageId);
      _pinnedFlashTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted || _flashingPinnedMessageId != messageId) return;
        setState(() => _flashingPinnedMessageId = null);
      });
    }

    if (_flashingPinnedMessageId == messageId) {
      setState(() => _flashingPinnedMessageId = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => activate());
    } else {
      activate();
    }
  }

  Widget _pinnedMessageFlash(String messageId, Widget child) {
    final active = _flashingPinnedMessageId == messageId;
    return AnimatedContainer(
      key: ValueKey('club-pinned-flash-$messageId'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      foregroundDecoration: BoxDecoration(
        color: active
            ? ChatsColors.fill.withValues(alpha: 0.48)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? ChatsColors.muted.withValues(alpha: 0.28)
              : Colors.transparent,
        ),
      ),
      child: child,
    );
  }

  /// The Board remains the sortable notice archive, while Chat shows the same
  /// announcement at the point it was posted. Keeping one message object in
  /// both views means pin, reaction and reply state can never drift apart.
  Widget _buildDesignChatAnnouncement(ChatMessage message) {
    final person = _designPerson(
      _personFor(chatStore.senderIdForViewer(message, _myId)),
    );
    final title = (message.title ?? '').trim();
    final body = message.content.trim();
    return KeyedSubtree(
      key: _designMessageAnchors.putIfAbsent(message.id, GlobalKey.new),
      child: SwipeToReply(
        key: ValueKey('club-swipe-reply-${message.id}'),
        enabled: _canWrite,
        onReply: () => _replyInChat(message),
        child: _pinnedMessageFlash(
          message.id,
          ClubNoticeCard(
            key: ValueKey('club-chat-announcement-${message.id}'),
            avatar: _designAvatar(person, 28),
            authorName: person.name,
            roleLabel: person.role,
            whenLabel: _designNoticeWhen(message.createdAt),
            title: title.isEmpty || title == body ? null : title,
            body: body,
            attachment: _designNoticeAttachment(message),
            pinned: message.pinned,
            reactions: {
              for (final entry in message.reactions.entries)
                entry.key: entry.value.length,
            },
            myReactions: {
              for (final entry in message.reactions.entries)
                if (entry.value.contains(_myId)) entry.key,
            },
            replyCount: chatStore.replyCountFor(message.id),
            onToggleReaction: _canWrite
                ? (emoji) => chatStore.toggleReaction(
                    messageId: message.id,
                    userId: _myId,
                    emoji: emoji,
                  )
                : null,
            onLongPress: () => _showDesignMessageActions(message),
            onOpenReplies: _canWrite ? () => _replyInChat(message) : null,
          ),
        ),
      ),
    );
  }

  Widget _buildDesignClubBubble(ChatMessage message, {required bool showTail}) {
    final mine = chatStore.isMessageOwner(message, _myId);
    final senderId = chatStore.senderIdForViewer(message, _myId);
    final person = _designPerson(_personFor(senderId));
    final available = MediaQuery.sizeOf(context).width - 32;
    final maxWidth = mine ? available * 0.776 : (available - 36) * 0.83;
    final seen = mine ? chatStore.seenCountFor(message) : 0;

    final bubble = ChatBubbleShell(
      key: ValueKey('club-message-bubble-${message.id}'),
      mine: mine,
      showTail: showTail,
      maxWidth: maxWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.replyToMessageId != null)
            _buildDesignQuote(message, mine: mine),
          if (message.content.trim().isNotEmpty)
            Text(message.content, style: chatBubbleTextStyle(mine: mine)),
          if (message.kind == ChatMessageKind.poll)
            ClubBubblePoll(
              key: ValueKey('club-bubble-poll-${message.id}'),
              question: (message.title ?? '').trim(),
              options: message.pollOptions,
              counts: [
                for (var i = 0; i < message.pollOptions.length; i++)
                  message.votesForOption(i),
              ],
              total: message.totalPollVotes,
              myChoice: message.pollViewerOption ?? message.pollVotes[_myId],
              closesLabel: _pollClosesLabel(message),
              mine: mine,
              closed: message.pollIsClosed,
              onVote: _canWrite
                  ? (index) => chatStore.votePoll(
                      messageId: message.id,
                      userId: _myId,
                      optionIndex: index,
                    )
                  : null,
            ),
        ],
      ),
    );

    return KeyedSubtree(
      key: _designMessageAnchors.putIfAbsent(message.id, GlobalKey.new),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: mine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  key: ValueKey('club-message-avatar-${message.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openProfile(message.senderId),
                  child: _designAvatar(person, 28),
                ),
              ),
            Flexible(
              child: Column(
                crossAxisAlignment: mine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              person.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: figtree(
                                size: 11,
                                weight: FontWeight.w600,
                                color: person.isClubAccount
                                    ? ChatsColors.accentText
                                    : chatSenderAccent(person.id),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SwipeToReply(
                    key: ValueKey('club-swipe-reply-${message.id}'),
                    enabled: _canWrite,
                    onReply: () => _replyInChat(message),
                    child: GestureDetector(
                      key: ValueKey('club-message-${message.id}'),
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _showDesignMessageActions(message),
                      child: _pinnedMessageFlash(message.id, bubble),
                    ),
                  ),
                  if (message.reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 5,
                        alignment: mine
                            ? WrapAlignment.end
                            : WrapAlignment.start,
                        children: [
                          for (final entry in message.reactions.entries)
                            GestureDetector(
                              key: ValueKey(
                                'club-bubble-reaction-${message.id}-${entry.key}',
                              ),
                              onTap: () => chatStore.toggleReaction(
                                messageId: message.id,
                                userId: _myId,
                                emoji: entry.key,
                              ),
                              child: Container(
                                height: 22,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: entry.value.contains(_myId)
                                      ? ChatsColors.accent.withValues(
                                          alpha: 0.10,
                                        )
                                      : ChatsColors.card,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: entry.value.contains(_myId)
                                        ? ChatsColors.accent
                                        : ChatsColors.border,
                                  ),
                                ),
                                // Align with both factors, not
                                // Container.alignment: a bare Align expands to
                                // the Wrap's loose width.
                                child: Align(
                                  widthFactor: 1,
                                  heightFactor: 1,
                                  child: Text(
                                    '${entry.key} ${entry.value.length}',
                                    style: figtree(
                                      size: 11,
                                      weight: FontWeight.w600,
                                      color: ChatsColors.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (mine && seen > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        S.clubSeenBy(seen),
                        style: figtree(
                          size: 10,
                          weight: FontWeight.w500,
                          color: ChatsColors.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesignQuote(ChatMessage message, {required bool mine}) {
    final senderId = message.replyToSenderId ?? '';
    final name = senderId == _myId
        ? S.you
        : _designPerson(_personFor(senderId)).name;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: message.content.trim().isEmpty ? 0 : 7),
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
            name,
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
              color: (mine ? ChatsColors.onAccent : ChatsColors.text)
                  .withValues(alpha: 0.82),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  /// `reply-preview` 143:75 — the banner above the composer.
  Widget _buildDesignReplyBanner(ChatMessage message) {
    final name = message.senderId == _myId
        ? S.you
        : _designPerson(_personFor(message.senderId)).name;
    return Container(
      key: const ValueKey('club-design-reply-banner'),
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
                  S.replyingTo(name),
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
                  ChatStore.replyPreviewFor(message),
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
            key: const ValueKey('club-design-cancel-reply'),
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

  bool _sameDesignDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _designDayLabel(DateTime value) {
    final now = DateTime.now();
    if (_sameDesignDay(now, value)) return S.today;
    if (_sameDesignDay(now.subtract(const Duration(days: 1)), value)) {
      return S.yesterday;
    }
    return DateFormat.MMMd(localeService.languageCode).format(value);
  }

  // ── Direct lane ────────────────────────────────────────────────────────────

  /// The Direct lane uses the same flat conversation rows as the Friends
  /// inbox. Access has already been reduced by [_soloChatEntries]: regular
  /// students see their own club thread, while board viewers see all inquiries.
  Widget _buildDesignDirectLane() {
    final entries = _soloChatEntries();
    if (entries.isEmpty) return _buildSoloChatLane(_t);
    return ListView.builder(
      key: const ValueKey('club-direct-chat-list'),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: entries.length,
      itemBuilder: (context, index) => _buildDesignDirectRow(entries[index]),
    );
  }

  /// `conversation-list` 335:39 — the board side of the same lane: every
  /// student thread, filtered by the header's search field.
  Widget _buildDesignDirectInbox() {
    final entries = _soloChatEntries(avatarSize: 48, plainPeerPreview: true);
    final query = _directQuery.trim().toLowerCase();
    final visible = query.isEmpty
        ? entries
        : entries
              .where(
                (entry) =>
                    entry.title.toLowerCase().contains(query) ||
                    entry.preview.toLowerCase().contains(query),
              )
              .toList();
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            entries.isEmpty ? S.clubDirectInboxEmpty : S.clubDirectNoMatches,
            textAlign: TextAlign.center,
            style: figtree(
              size: 14,
              weight: FontWeight.w500,
              color: ChatsColors.muted,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('club-direct-inbox-list'),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final entry = visible[index];
        return ClubDirectInboxRow(
          key: ValueKey('club-direct-inbox-row-${entry.threadId}'),
          avatar: entry.avatar,
          name: entry.title,
          whenLabel: entry.whenLabel,
          preview: entry.preview,
          unread: entry.unread > 0,
          onTap: () => unawaited(_openSoloChatThread(entry.threadId)),
        );
      },
    );
  }

  Widget _buildDesignDirectRow(ClubSoloChatEntry entry) {
    final unread = entry.unread > 0;
    return Material(
      color: unread ? ChatsColors.unreadRow : Colors.transparent,
      child: InkWell(
        key: ValueKey('club-solo-chat-row-${entry.threadId}'),
        onTap: () => unawaited(_openSoloChatThread(entry.threadId)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ChatsColors.border)),
          ),
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                const SizedBox(width: 20),
                SizedBox(width: 44, height: 44, child: entry.avatar),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: figtree(
                          size: 14,
                          weight: unread ? FontWeight.w700 : FontWeight.w600,
                          color: ChatsColors.text,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: figtree(
                          size: 13,
                          weight: unread ? FontWeight.w500 : FontWeight.w400,
                          color: unread ? ChatsColors.text : ChatsColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  height: 37,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        entry.whenLabel,
                        style: figtree(
                          size: 11,
                          weight: unread ? FontWeight.w600 : FontWeight.w500,
                          color: unread
                              ? ChatsColors.accentText
                              : ChatsColors.muted,
                        ),
                      ),
                      const Spacer(),
                      if (unread)
                        Container(
                          key: ValueKey(
                            'club-direct-chat-unread-${entry.threadId}',
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: ChatsColors.accent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Align(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: Text(
                              entry.unread > 9 ? '9+' : '${entry.unread}',
                              style: figtree(
                                size: 10,
                                weight: FontWeight.w700,
                                color: ChatsColors.onAccent,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── sheets ─────────────────────────────────────────────────────────────────

  /// `club-message-actions` 146:3. Edit Message and Forward are on the frame
  /// but not here: nothing in the app can rewrite a sent message, and
  /// forwarding needs a thread picker the handoff does not draw. Save Message
  /// is device-local — see `chat_group_prefs.dart`.
  void _showDesignMessageActions(ChatMessage message) {
    final saved = chatGroupPrefs.isMessageSaved(message.id);
    showClubMessageActions(
      context,
      quickEmojis: _quickReactions.take(5).toList(),
      myReactions: {
        for (final entry in message.reactions.entries)
          if (entry.value.contains(_myId)) entry.key,
      },
      onReact: (emoji) => chatStore.toggleReaction(
        messageId: message.id,
        userId: _myId,
        emoji: emoji,
      ),
      onMoreEmoji: () => _showDesignMessageActions(message),
      actions: [
        if (_canWrite)
          ClubMessageAction(
            rowKey: ValueKey('club-reply-message-${message.id}'),
            icon: Icons.reply_rounded,
            label: message.kind == ChatMessageKind.announcement
                ? S.boardReplyInChat
                : S.replyAction,
            onTap: () => _replyInChat(message),
          ),
        if (_canModerate)
          ClubMessageAction(
            rowKey: ValueKey('club-pin-message-${message.id}'),
            icon: message.pinned
                ? Icons.push_pin
                : Icons.bookmark_border_rounded,
            label: message.pinned ? S.clubUnpinMessage : S.clubPinMessage,
            onTap: () => chatStore.setPinned(message.id, !message.pinned),
          ),
        ClubMessageAction(
          rowKey: ValueKey('club-save-message-${message.id}'),
          icon: saved ? Icons.star_rounded : Icons.star_outline_rounded,
          label: saved ? S.clubUnsaveMessage : S.clubSaveMessage,
          onTap: () {
            chatGroupPrefs.setMessageSaved(message.id, !saved);
            if (!saved && mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(S.clubMessageSaved),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
          },
        ),
        if (message.content.isNotEmpty)
          ClubMessageAction(
            rowKey: ValueKey('club-copy-message-${message.id}'),
            icon: Icons.copy_rounded,
            label: S.copyText,
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.content));
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(S.copied)));
            },
          ),
        ClubMessageAction(
          rowKey: ValueKey('club-profile-message-${message.id}'),
          icon: Icons.person_outline_rounded,
          label: S.viewProfile,
          onTap: () => _openProfile(message.senderId),
        ),
        if (!chatStore.isMessageOwner(message, _myId))
          ClubMessageAction(
            rowKey: ValueKey('club-report-message-${message.id}'),
            icon: Icons.flag_outlined,
            label: S.clubReportMessage,
            destructive: true,
            onTap: () => unawaited(_reportDesignMessage(message)),
          ),
        if (chatStore.isMessageOwner(message, _myId))
          ClubMessageAction(
            rowKey: ValueKey('club-delete-message-${message.id}'),
            icon: Icons.delete_outline_rounded,
            label: S.clubDeleteForEveryone,
            destructive: true,
            onTap: () => unawaited(_confirmDeleteMessage(message)),
          ),
      ],
    );
  }

  /// Reported to the **local** moderation log, like the group report: there is
  /// no `club_message` target in the remote schema.
  Future<void> _reportDesignMessage(ChatMessage message) async {
    final reason = await showModerationReasonSheet(
      context,
      title: S.clubReportMessage,
    );
    if (reason == null || !mounted) return;
    await adminModerationService.recordReport(
      reporterId: _myId,
      targetType: 'club_message',
      targetId: message.id,
      reason: reason,
      reportedUserId: message.senderId,
      reportedClubId: _club?.id,
      contentSnapshot: message.content,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.userReported),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// `club-attachment-sheet` 146:298. The frame offers six tiles; three of them
  /// have nowhere to go in this app and are left off rather than faked — File
  /// (no file-picker dependency), Event (events deliberately left this surface
  /// with the Board + Chat design) and Location (no such field on a message).
  Future<void> _openDesignShareSheet() async {
    final club = _club;
    if (club == null) return;
    final clubSide = _isClubSideSession;
    final memberCount =
        supabaseClubMemberCounts[club.id] ??
        _communityInfo?.memberCount ??
        clubMemberCount(club.id);
    await showClubShareSheet(
      context,
      clubName: club.name,
      visibilityLine: S.clubShareVisibility(memberCount),
      options: [
        ClubShareOption(
          tileKey: const ValueKey('club-share-photo'),
          icon: Icons.image_outlined,
          label: clubSide ? S.attachMedia : S.attachPhoto,
          onTap: () => unawaited(_handleAttachment(ClubAttachment.photo)),
        ),
        ClubShareOption(
          tileKey: const ValueKey('club-share-camera'),
          icon: Icons.photo_camera_outlined,
          label: S.takePhoto,
          onTap: () => unawaited(
            clubSide
                ? _pickMediaAttachment(useCamera: true)
                : _handleAttachment(ClubAttachment.photo),
          ),
        ),
        ClubShareOption(
          tileKey: const ValueKey('club-share-poll'),
          icon: Icons.bar_chart_rounded,
          label: S.attachPoll,
          onTap: () => unawaited(_handleAttachment(ClubAttachment.poll)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      backgroundColor: _designClubRoom ? ChatsColors.background : t.body,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          chatStore,
          userState,
          rsvpStore,
          ?_communityInfo,
        ]),
        builder: (context, _) {
          final club = _club;
          final canAccess = chatStore.canAccessThread(widget.threadId, _myId);
          final canOfferStudentJoin =
              club != null && !canAccess && authService.isStudentSession;
          if (club == null || (!canAccess && !canOfferStudentJoin)) {
            return SafeArea(bottom: false, child: _buildUnavailable(t));
          }
          if (!canAccess) {
            // Non-members get no Board and no Chat — only the invitation to
            // join, which is what the club profile offers them too.
            return SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(club, t),
                  Expanded(child: _buildJoinPrompt(club, t)),
                ],
              ),
            );
          }
          if (_designClubRoom) {
            return SafeArea(
              top: false,
              bottom: false,
              child: _buildDesignRoom(club),
            );
          }
          return SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                _buildHeader(club, t),
                ClubLaneSwitch(
                  tab: _tab,
                  onTab: _switchTab,
                  boardUnread: _laneUnread(ClubChatLane.board),
                  chatUnread: _laneUnread(ClubChatLane.chat),
                  soloUnread: _soloChatEntries().fold<int>(
                    0,
                    (total, entry) => total + entry.unread,
                  ),
                  t: t,
                ),
                Expanded(
                  child: _tab == ClubCommunityTab.board
                      ? _buildBoardLane(t)
                      : _tab == ClubCommunityTab.chat
                      ? _buildChatLane(t)
                      : _buildSoloChatLane(t),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(Club club, ClubChatTheme t) {
    final memberCount =
        supabaseClubMemberCounts[club.id] ??
        _communityInfo?.memberCount ??
        clubMemberCount(club.id);
    return ClubCommunityHeader(
      club: club,
      avatarColor: _accent,
      memberCount: memberCount,
      viewerRoleTitle: studentClubRoleService.roleTitleFor(club, _myId),
      // Inside the room the identity is not a link out: tapping it opens the
      // Chat lane. The club profile lives behind the ••• menu.
      onOpenClub: () => _switchTab(ClubCommunityTab.chat),
      t: t,
      // The main navigation deliberately extends tab content edge-to-edge and
      // does not wrap it in a top SafeArea. Embedded club rooms therefore need
      // the same stable status-bar/notch inset as pushed rooms; otherwise the
      // identity and action buttons sit underneath the system UI.
      topInset: MediaQuery.viewPaddingOf(context).top,
      muted: clubChatPrefs.isMuted(widget.threadId),
      onBack: widget.embedded ? null : () => Navigator.maybePop(context),
      onToggleMute: () => clubChatPrefs.setMuted(
        widget.threadId,
        !clubChatPrefs.isMuted(widget.threadId),
      ),
      onMessagePrivately: authService.isStudentSession && !_canPostNotice
          ? () => unawaited(_messageClubPrivately())
          : null,
      onOpenSettings: _openSettingsSheet,
    );
  }

  /// The count on a segment: what is waiting in the lane the reader is not
  /// looking at. The lane on screen is being read, so it shows nothing.
  int _laneUnread(ClubChatLane lane) {
    final tab = lane == ClubChatLane.board
        ? ClubCommunityTab.board
        : ClubCommunityTab.chat;
    if (_tab == tab) return 0;
    return chatStore.unreadInClubLane(widget.threadId, _myId, lane);
  }

  Widget _buildSoloChatLane(ClubChatTheme t) {
    final entries = _soloChatEntries();
    return ClubSoloChatLane(
      showAll: _canModerate,
      entries: entries,
      t: t,
      onOpen: (threadId) => unawaited(_openSoloChatThread(threadId)),
      onStart: _canModerate ? null : () => unawaited(_messageClubPrivately()),
    );
  }

  // ── Board lane ──────────────────────────────────────────────────────────────

  /// One grouped list of notices — pinned ("Always here"), then new, then
  /// earlier — with the composer or the route into Chat underneath.
  Widget _buildBoardLane(ClubChatTheme t) {
    final notices = chatStore.noticesIn(widget.threadId);
    final pinned = notices.where((notice) => notice.pinned).toList();
    final rest = notices.where((notice) => !notice.pinned).toList();
    final fresh = rest
        .where((notice) => _unreadNoticeIds.contains(notice.id))
        .toList();
    final earlier = rest
        .where((notice) => !_unreadNoticeIds.contains(notice.id))
        .toList();

    return Column(
      children: [
        Expanded(
          child: notices.isEmpty
              ? ClubBoardEmpty(t: t, canPost: _canPostNotice)
              : ListView(
                  key: const ValueKey('club-board-list'),
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
                  children: [
                    if (pinned.isNotEmpty) ...[
                      ClubBoardLabel(label: S.boardGroupPinned, t: t),
                      _noticeGroup(pinned, t),
                    ],
                    if (fresh.isNotEmpty) ...[
                      ClubBoardLabel(
                        label: S.boardGroupNew(fresh.length),
                        t: t,
                        top: pinned.isNotEmpty,
                      ),
                      _noticeGroup(fresh, t),
                    ],
                    if (earlier.isNotEmpty) ...[
                      ClubBoardLabel(
                        label: S.boardGroupEarlier,
                        t: t,
                        top: pinned.isNotEmpty || fresh.isNotEmpty,
                      ),
                      _noticeGroup(earlier, t),
                    ],
                  ],
                ),
        ),
        if (_canPostNotice)
          ClubBoardPostBar(
            t: t,
            onPost: () => unawaited(_composeAnnouncement()),
          )
        else
          // No disabled button for a member without a role — the strip states
          // the rule and doubles as the doorway into Chat.
          ClubBoardLockedStrip(
            t: t,
            onGoToChat: () => _switchLane(ClubChatLane.chat),
          ),
      ],
    );
  }

  Widget _noticeGroup(List<ChatMessage> notices, ClubChatTheme t) {
    return ClubNoticeGroup(
      t: t,
      rows: [
        for (var i = 0; i < notices.length; i++)
          _noticeRow(notices[i], t, last: i == notices.length - 1),
      ],
    );
  }

  Widget _noticeRow(ChatMessage notice, ClubChatTheme t, {required bool last}) {
    final author = _personFor(notice.senderId);
    return ClubNoticeRow(
      key: ValueKey('club-notice-row-${notice.id}'),
      message: notice,
      author: author,
      avatar: _avatarFor(author, 22),
      whenLabel:
          '${_dayLabel(notice.createdAt)} · '
          '${_timeLabel(notice.createdAt)}',
      unread: _unreadNoticeIds.contains(notice.id),
      replyCount: chatStore.replyCountFor(notice.id),
      replyEnabled: _canWrite,
      showRoles: clubChatPrefs.showRoles,
      last: last,
      t: t,
      onReplyInChat: () => _replyInChat(notice),
      onLongPress: () => _showMessageActions(notice),
      onOpenAuthor: () => _openParticipantProfile(author),
      attachments: [
        if (notice.kind == ChatMessageKind.announcement &&
            notice.attachmentPath != null)
          notice.attachmentName != null &&
                  _looksLikeImage(notice.attachmentName!)
              ? ClubPhotoAttachment(path: notice.attachmentPath!, t: t)
              : isVideoMediaPath(
                  notice.attachmentName ?? notice.attachmentPath!,
                )
              ? ClubVideoAttachment(path: notice.attachmentPath!, t: t)
              : ClubFileChip(
                  message: notice,
                  t: t,
                  onOpen: () => _showMessageActions(notice),
                ),
      ],
      reactions: notice.reactions.isEmpty ? null : _reactionsFor(notice, t),
    );
  }

  static bool _looksLikeImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic');
  }

  // ── Chat lane ───────────────────────────────────────────────────────────────

  Widget _buildChatLane(ClubChatTheme t) {
    return Column(
      children: [
        Expanded(child: _buildStream(t)),
        if (_canWrite)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingTo case final replied?)
                _clubComposerReplyPreview(replied, t),
              ClubComposer(
                controller: _inputController,
                t: t,
                hintText: S.communityComposerHint,
                people: _members,
                avatarBuilder: _avatarFor,
                onSend: _send,
                onAttach: (attachment) =>
                    unawaited(_handleAttachment(attachment)),
                onTypingChanged: _onTypingDraftChanged,
                onFocusChanged: (focused) =>
                    _typingSession?.updateFocus(focused),
              ),
            ],
          )
        else
          Container(
            key: const ValueKey('club-chat-locked-strip'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 16),
            decoration: BoxDecoration(
              color: t.body,
              border: Border(top: BorderSide(color: t.hair)),
            ),
            child: SafeArea(
              top: false,
              child: Text(
                S.clubChannelReadOnly,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.sub,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _withChatBackground(ClubChatTheme t, Widget child) {
    final background = clubChatPrefs.backgroundFor(widget.threadId);
    return Container(
      key: ValueKey('club-chat-background-${background.name}'),
      decoration: BoxDecoration(gradient: _backgroundGradient(background, t)),
      // The same campus wallpaper the student threads use, painted over the
      // club's chosen gradient so every option keeps its own tint. The ink
      // follows the club accent, matching the rest of the community theme.
      child: ChatCampusBackdrop(
        isDark: t.isDark,
        accent: t.accent,
        child: child,
      ),
    );
  }

  Widget _buildStream(ClubChatTheme t) {
    final messages = chatStore.messagesFor(widget.threadId, viewerId: _myId);
    final typing = chatStore
        .typingUserIds(widget.threadId, excluding: _myId)
        .map(_personFor)
        .toList();

    if (messages.isEmpty && typing.isEmpty) {
      final club = _club;
      // Same composition as an empty student thread: the room's own face, its
      // name, and one quiet line — no card on top of the wallpaper.
      return _withChatBackground(
        t,
        Stack(
          children: [
            _glow(t),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  key: const ValueKey('club-empty-conversation'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: t.red.withValues(alpha: t.isDark ? 0.13 : 0.07),
                        shape: BoxShape.circle,
                      ),
                      child: club == null
                          ? Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: t.red,
                              size: 40,
                            )
                          : ClubAvatar(
                              clubId: club.id,
                              clubName: club.name,
                              color: _accent,
                              imageUrl: club.logoUrl,
                              size: 72,
                              fontSize: 27,
                              shape: 'circle',
                            ),
                    ),
                    if (club != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        club.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.25,
                          color: t.text,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      S.sayHello,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final items = _buildStreamItems(messages, typing, t);
    final childIndexByKey = <Key, int>{
      for (var i = 0; i < items.length; i++)
        ?items[i].key: items.length - 1 - i,
    };
    return _withChatBackground(
      t,
      Stack(
        children: [
          _glow(t),
          ListView.builder(
            controller: _scrollController,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
            itemCount: items.length,
            findChildIndexCallback: (key) => childIndexByKey[key],
            itemBuilder: (context, index) => items[items.length - 1 - index],
          ),
          if (_showJumpButton)
            Positioned(
              right: 14,
              bottom: 14,
              child: Semantics(
                button: true,
                label: S.jumpToLatest,
                child: GestureDetector(
                  key: const ValueKey('club-jump-to-latest'),
                  onTap: _scrollToLatest,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.sheet,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.borderB),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: t.red,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _glow(ClubChatTheme t) => Positioned(
    top: -20,
    left: 0,
    right: 0,
    height: 150,
    child: IgnorePointer(
      child: Center(
        child: Container(
          width: 280,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [t.glow, t.glow.withValues(alpha: 0)],
              stops: const [0, 0.7],
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _buildStreamItems(
    List<ChatMessage> messages,
    List<ClubPerson> typing,
    ClubChatTheme t,
  ) {
    final items = <Widget>[];
    final style = clubChatPrefs.messageStyle;
    final showRoles = clubChatPrefs.showRoles;

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final previous = i > 0 ? messages[i - 1] : null;
      final newDay =
          previous == null || !_sameDay(previous.createdAt, message.createdAt);
      if (newDay) {
        items.add(ClubDayMark(label: _dayLabel(message.createdAt), t: t));
      }
      if (_unreadAtOpen > 0 && message.id == _unreadAnchorMessageId) {
        items.add(
          KeyedSubtree(
            key: _unreadDividerKey,
            child: ClubUnreadDivider(count: _unreadAtOpen, t: t),
          ),
        );
      }

      switch (message.kind) {
        case ChatMessageKind.system:
          items.add(ClubSystemLine(label: message.content, t: t));
        case ChatMessageKind.announcement:
          final author = _personFor(message.senderId);
          items.add(
            ClubAnnouncementCard(
              message: message,
              author: author,
              avatar: _avatarFor(author, 24),
              t: t,
              emphasis: clubChatPrefs.announcementEmphasis,
              showRoles: showRoles,
              timeLabel: _timeLabel(message.createdAt),
              replyCount: chatStore.replyCountFor(message.id),
              onReplyInChat: _canWrite ? () => _replyInChat(message) : null,
              onLongPress: () => _showMessageActions(message),
              onOpenAuthor: () => _openParticipantProfile(author),
              reactions: message.reactions.isEmpty
                  ? null
                  : _reactionsFor(message, t),
            ),
          );
        case ChatMessageKind.poll:
          final author = _personFor(message.senderId);
          items.add(
            ClubPollMessageCard(
              message: message,
              author: author,
              avatar: _avatarFor(author, 20),
              t: t,
              myId: _myId,
              showRoles: showRoles,
              closesLabel: _pollClosesLabel(message),
              onVote: (index) => chatStore.votePoll(
                messageId: message.id,
                userId: _myId,
                optionIndex: index,
              ),
              onLongPress: () => _showMessageActions(message),
              onOpenAuthor: () => _openParticipantProfile(author),
            ),
          );
        case ChatMessageKind.event:
          final event = _eventById(message.eventId);
          if (event != null) {
            items.add(_eventCard(event));
            break;
          }
          items.add(_messageGroup(message, previous, style, showRoles, t));
        case ChatMessageKind.text:
        case ChatMessageKind.postShare:
        case ChatMessageKind.photo:
        case ChatMessageKind.file:
          items.add(_messageGroup(message, previous, style, showRoles, t));
      }
    }

    if (typing.isNotEmpty) {
      items.add(_typingBubble(typing));
    }
    return items;
  }

  Widget _reactionsFor(ChatMessage message, ClubChatTheme t) =>
      ClubReactionsRow(
        message: message,
        myId: _myId,
        t: t,
        onToggle: (emoji) => chatStore.toggleReaction(
          messageId: message.id,
          userId: _myId,
          emoji: emoji,
        ),
        onPick: () => _showMessageActions(message),
      );

  Widget _messageGroup(
    ChatMessage message,
    ChatMessage? previous,
    ClubMessageStyle style,
    bool showRoles,
    ClubChatTheme t,
  ) {
    final sender = _personFor(message.senderId);
    // A club admin is the authenticated actor, but the public community
    // message is authored by the club. Keep ownership separate for actions
    // such as delete, while rendering the club account as an incoming sender
    // so its logo and identity remain visible to everyone — including the
    // admin who sent it.
    final isClubAuthoredMessage =
        ChatStore.isClubThread(message.threadId) && sender.isClubAccount;
    final mine =
        !isClubAuthoredMessage && chatStore.isMessageOwner(message, _myId);
    final head =
        !mine ||
        previous == null ||
        previous.senderId != message.senderId ||
        previous.kind != ChatMessageKind.text ||
        message.kind != ChatMessageKind.text ||
        message.replyToMessageId != null ||
        message.mentions.isNotEmpty ||
        !_sameDay(previous.createdAt, message.createdAt);

    return SentMessageEntrance(
      key: ValueKey('sent-message-entrance-${message.id}'),
      animate: _animatingSentMessageIds.contains(message.id),
      onCompleted: () => _finishSentMessageEntrance(message.id),
      child: SwipeToReply(
        key: ValueKey('club-swipe-reply-${message.id}'),
        enabled: _canWrite,
        onReply: () => _replyInChat(message),
        child: ClubMessageGroup(
          key: ValueKey('club-message-${message.id}'),
          message: message,
          sender: sender,
          avatar: _avatarFor(sender, 30),
          mine: mine,
          head: head,
          style: style,
          showRoles: showRoles,
          timeLabel: _timeLabel(message.createdAt),
          flagged: message.mentionsUser(_myId) && !mine,
          t: t,
          replySenderName: message.replyToSenderId == null
              ? null
              : _personFor(message.replyToSenderId!).name,
          onLongPress: () => _showMessageActions(message),
          onOpenSender: () => _openParticipantProfile(sender),
          onUserLinkTap: _openSharedUserProfile,
          statusLabel: mine
              ? (chatStore.seenCountFor(message) > 1 ? S.seen : S.delivered)
              : null,
          attachments: [
            if (message.kind == ChatMessageKind.photo &&
                message.attachmentPath != null)
              ClubPhotoAttachment(path: message.attachmentPath!, t: t),
            if (message.kind == ChatMessageKind.file &&
                message.attachmentPath != null &&
                isVideoMediaPath(
                  message.attachmentName ?? message.attachmentPath!,
                ))
              ClubVideoAttachment(path: message.attachmentPath!, t: t),
            if (message.kind == ChatMessageKind.file &&
                message.attachmentPath != null &&
                !isVideoMediaPath(
                  message.attachmentName ?? message.attachmentPath!,
                ))
              ClubFileChip(
                message: message,
                t: t,
                onOpen: () => _showMessageActions(message),
              ),
            if (message.kind == ChatMessageKind.postShare &&
                message.sharedPostId != null)
              SharedPostMessageCard(postId: message.sharedPostId!),
          ],
          reactions: message.reactions.isEmpty
              ? null
              : _reactionsFor(message, t),
        ),
      ),
    );
  }

  Widget _eventCard(Event event, {bool compact = false, VoidCallback? onOpen}) {
    final t = _t;
    return ClubEventCard(
      key: ValueKey('club-event-${event.id}'),
      title: event.title,
      dayLabel: S.weekdayShort(event.dateTime.weekday),
      dateLabel: '${event.dateTime.day} ${S.monthShort(event.dateTime.month)}',
      clockLabel: _timeLabel(event.dateTime),
      place: event.location,
      goingCount: event.attendeeUserIds.length,
      going: rsvpStore.isAttending(event.id),
      t: t,
      compact: compact,
      audienceBadge: audienceForEvent(event) == ContentAudience.everyone
          ? null
          : ContentAudiencePill(
              key: ValueKey('content-audience-pill-${event.id}'),
              audience: audienceForEvent(event),
              // `t.accent` is the raw club colour; `t.red` is the same accent
              // corrected for legibility on this surface.
              accent: t.accent,
              foreground: t.red,
            ),
      onToggleRsvp: () => _toggleRsvp(event),
      onOpen: onOpen ?? () => _openEvent(event),
    );
  }

  Widget _buildJoinPrompt(Club club, ClubChatTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClubAvatar(
              clubId: club.id,
              clubName: club.name,
              color: _accent,
              imageUrl: club.logoUrl,
              size: 72,
              fontSize: 28,
              shape: 'circle',
            ),
            const SizedBox(height: 18),
            Text(
              S.joinToChat,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.joinToChatHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: t.textMuted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 180,
              height: 44,
              child: ClubFollowButton(clubId: club.id, size: 'large'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailable(ClubChatTheme t) {
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
                color: t.textMuted,
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
                  Icon(Icons.lock_outline_rounded, size: 44, color: t.sub),
                  const SizedBox(height: 14),
                  Text(
                    AppLocalizations.of(context)!.conversationUnavailableTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    AppLocalizations.of(context)!.conversationUnavailableBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: t.textMuted,
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

  // ── Labels ──────────────────────────────────────────────────────────────────

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _firstName(String name) => name.split(RegExp(r'\s+')).first;

  String _dayLabel(DateTime value) {
    final now = DateTime.now();
    if (_sameDay(value, now)) return S.today;
    if (_sameDay(value, now.subtract(const Duration(days: 1)))) {
      return S.yesterday;
    }
    return '${value.day} ${S.monthShort(value.month)}';
  }

  String _timeLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _pollClosesLabel(ChatMessage message) {
    final closes = message.pollClosesAt;
    if (closes == null) return '';
    if (message.pollIsClosed) return S.pollClosed;
    final remaining = closes.difference(DateTime.now());
    if (remaining.inHours < 24) {
      return S.pollCloses(S.pollHours(remaining.inHours.clamp(1, 23)));
    }
    return S.pollCloses(S.pollDays(remaining.inDays.clamp(1, 365)));
  }
}

// ── Small shared pieces ──────────────────────────────────────────────────────

class _SheetField extends StatelessWidget {
  const _SheetField({
    super.key,
    required this.hint,
    required this.t,
    required this.onChanged,
    this.maxLines = 1,
    this.autofocus = false,
  });

  final String hint;
  final ClubChatTheme t;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.input,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: TextField(
        autofocus: autofocus,
        maxLines: maxLines,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(fontSize: 14.5, color: t.text),
        decoration: InputDecoration(
          // The container above paints the club-tinted input background; the
          // global inputDecorationTheme would stack a neutral grey over it.
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 14.5, color: t.sub),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.t,
    required this.onTap,
  });

  final String label;
  final ClubChatTheme t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: t.meGradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.t,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final ClubChatTheme t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: t.red),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

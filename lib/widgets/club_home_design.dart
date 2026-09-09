import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../models/club.dart';
import '../models/news_post.dart';
import '../screens/club_profile_screen.dart';
import '../screens/create_post_screen.dart' show buildPostBanner;
import '../services/account_switcher_service.dart';
import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/club_notification_service.dart';
import '../services/comment_store.dart';
import '../services/content_safety_service.dart';
import '../services/content_store.dart';
import '../services/image_aspect_ratio.dart';
import '../services/mock_data.dart';
import '../services/post_like_helper.dart';
import '../services/supabase_post_service.dart';
import '../services/theme_service.dart';
import '../services/user_state.dart';
import '../services/view_tracker.dart';
import 'club_avatar.dart';
import 'clubup_design.dart';
import 'expandable_post_caption.dart';
import 'home_comments_sheet.dart';
import 'home_share_sheet.dart';
import 'poll_card.dart';
import '../models/content_audience.dart';
import '../services/content_visibility.dart';
import 'content_audience_sheet.dart';

/// The CLUB HOME area of the ClubUp-Desings handoff — `home-feed-alt-light` /
/// `home-feed-alt-dark` (Figma `272:31` / `272:200`, with the typed-composer
/// state `305:468` / `305:619`), plus the `admin-compose` card `298:5`.
///
/// This is the *club* point of view on Home: the club-admin login and a
/// student who has switched to their club account. Its composer remains
/// club-specific; the header and feed use the shared student Home components
/// for one consistent layout.

// ── tokens ───────────────────────────────────────────────────────────────────

/// Sampled straight out of the two frame PNGs. The dark ramp is the profile
/// section's zinc (`#09090B` / `#18181B` / `#27272A`) rather than
/// [ClubUpColors]' approximated `#121212` / `#1E1E1E` / `#2D2D2D`, and the
/// compose card sits one step below the post cards on `#141417`.
class ClubHomeColors {
  const ClubHomeColors._();

  static bool get _dark => themeService.isDark;

  /// Page background — shared with the rest of the redesigned app.
  static Color get page => ClubUpColors.background;

  /// `design-society-post` surface — `#FFFFFF` / `#18181B`.
  static Color get card => _dark ? const Color(0xFF18181B) : Colors.white;

  /// `admin-compose` surface — `#FFFFFF` / `#141417`.
  static Color get composeCard =>
      _dark ? const Color(0xFF141417) : Colors.white;

  /// Header hairline, card border, interaction-row rule — `#E4E4E7` /
  /// `#27272A`.
  static Color get border =>
      _dark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);

  /// Primary text — `#18181B` / `#FAFAFA`.
  static Color get text =>
      _dark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);

  /// Secondary text and every un-acted icon — `#71717A` / `#A1A1AA`.
  static Color get muted =>
      _dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);

  /// The one accent. Unchanged in dark: the frame's Post button and wordmark
  /// are both `#800020` on `#09090B`.
  static const Color accent = Color(0xFF800020);

  /// `floating-club-badge` fill — the frame blurs the photo behind it, so this
  /// is a translucent surface, not a flat one.
  static Color get badgeSurface =>
      _dark ? const Color(0xA818181B) : const Color(0xCCFFFFFF);

  static Color get badgeBorder =>
      _dark ? const Color(0x33FAFAFA) : const Color(0xE6FFFFFF);

  /// `admin-compose` lift — `0 8px 8px rgba(0,0,0,0.03)`.
  static List<BoxShadow> get composeShadow => [
    BoxShadow(
      color: _dark ? const Color(0x59000000) : const Color(0x08000000),
      offset: const Offset(0, 8),
      blurRadius: 8,
    ),
  ];

  /// Post-card lift — `0 8px 16px rgba(0,0,0,0.03)`.
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: _dark ? const Color(0x59000000) : const Color(0x08000000),
      offset: const Offset(0, 8),
      blurRadius: 16,
    ),
  ];
}

/// `feed-scroller-content` gutters: 20pt sides, 20pt between cards.
const double kClubHomeGutter = 20;

// ── header ───────────────────────────────────────────────────────────────────

/// `premium-header-container` `272:42` — a flat band with the wordmark and the
/// notification bell. The student header's greeting/dropdown row is not here:
/// this frame prints the greeting below the band instead, and has no
/// feed-scope switcher at all.
class ClubHomeHeader extends StatelessWidget {
  const ClubHomeHeader({
    super.key,
    required this.unreadCount,
    required this.onBellTap,
    this.overlay,
  });

  final int unreadCount;
  final VoidCallback onBellTap;

  /// Pull-to-refresh spinner, centred in the band like the student header's.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('club-home-header'),
      decoration: BoxDecoration(
        color: ClubHomeColors.page,
        border: Border(bottom: BorderSide(color: ClubHomeColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        kClubHomeGutter,
        12,
        kClubHomeGutter,
        16,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ClubUp',
                  key: const ValueKey('club-home-wordmark'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 22,
                    weight: FontWeight.w800,
                    color: ClubHomeColors.accent,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              _ClubHomeBellChip(unreadCount: unreadCount, onTap: onBellTap),
            ],
          ),
          if (overlay != null) IgnorePointer(child: overlay!),
        ],
      ),
    );
  }
}

/// `notification-trigger` / `icon-bell` `272:51` — a 36pt bordered chip with an
/// 8pt accent dot, not a count badge.
class _ClubHomeBellChip extends StatelessWidget {
  const _ClubHomeBellChip({required this.unreadCount, required this.onTap});

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('club-home-notifications-bell'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ClubHomeColors.card,
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              border: Border.all(color: ClubHomeColors.border),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.notifications_none_rounded,
                    size: 20,
                    color: ClubHomeColors.text,
                    semanticLabel: AppLocalizations.of(context)!.notifications,
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 1,
                    right: 1,
                    child: Container(
                      key: const ValueKey('club-home-bell-dot'),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: ClubHomeColors.accent,
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `categories-horizontal-track` `272:56` — the "Hi, ..." greeting. The name is a
/// leftover from the frame this was duplicated off; it draws the greeting.
class ClubHomeGreeting extends StatelessWidget {
  const ClubHomeGreeting({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kClubHomeGutter,
        14,
        kClubHomeGutter,
        10,
      ),
      child: Row(
        children: [
          Text(
            S.hiPrefix,
            key: const ValueKey('club-home-greeting-prefix'),
            style: figtree(
              size: 15,
              weight: FontWeight.w500,
              color: ClubHomeColors.muted,
            ),
          ),
          const SizedBox(width: 6),
          // Club names run long — the frame's fixed 393pt would clip
          // "Koç University Entrepreneurship Society" outright.
          Expanded(
            child: Text(
              name,
              key: const ValueKey('club-home-greeting-name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figtree(
                size: 16,
                weight: FontWeight.w700,
                color: ClubHomeColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── composer ─────────────────────────────────────────────────────────────────

/// `admin-compose` `298:5`, in both its states: the placeholder row of
/// `272:31` and the typed paragraph of `305:468`.
///
/// The field stays live on Home. Gallery selection also stays inline as a
/// thumbnail; Post opens a confirmation preview and only its Confirm action
/// publishes through [supabasePostService.createPost].
class ClubHomeComposerCard extends StatefulWidget {
  const ClubHomeComposerCard({
    super.key,
    required this.club,
    required this.onPosted,
  });

  final Club club;
  final VoidCallback onPosted;

  @override
  State<ClubHomeComposerCard> createState() => _ClubHomeComposerCardState();
}

class _ClubHomeComposerCardState extends State<ClubHomeComposerCard> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _imagePath;
  bool _pickingPhoto = false;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _reviewPost() async {
    final content = _controller.text.trim();
    final hasPhoto = _imagePath != null && _imagePath!.isNotEmpty;
    if (content.isEmpty && !hasPhoto) {
      _focusNode.requestFocus();
      return;
    }
    if (_posting) return;
    _focusNode.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ClubHomePostPreviewDialog(
        club: widget.club,
        content: content,
        imagePath: _imagePath,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _publishPost(content);
  }

  Future<void> _publishPost(String content) async {
    setState(() => _posting = true);
    try {
      final post = await supabasePostService.createPost(
        reservedPostId: const Uuid().v4(),
        clubId: widget.club.id,
        authorId: accountSwitcherService.actorId,
        content: content,
        taggedClubIds: const [],
        taggedUserIds: const [],
        imagePath: _imagePath,
      );
      if (!mounted) return;
      newsPosts.insert(0, post);
      unawaited(contentStore.saveNewsPosts());
      contentStore.notifyContentChanged();
      if (!supabasePostService.isAvailable) {
        unawaited(clubNotificationService.notifyFollowersAboutPost(post));
      }
      _controller.clear();
      _imagePath = null;
      _focusNode.unfocus();
      HapticFeedback.lightImpact();
      setState(() => _posting = false);
      widget.onPosted();
    } catch (error) {
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error is ContentSafetyException
                  ? AppLocalizations.of(context)!.contentSafetyRejected
                  : AppLocalizations.of(context)!.publishErrorGeneric,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _pickPhoto() async {
    if (_pickingPhoto || _posting) return;
    _focusNode.unfocus();
    setState(() => _pickingPhoto = true);
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (photo == null || !mounted) return;
      setState(() => _imagePath = photo.path);
      HapticFeedback.selectionClick();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.couldNotOpenThisPage),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _removePhoto() {
    setState(() => _imagePath = null);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('club-home-composer'),
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClubAvatar(
                clubId: widget.club.id,
                clubName: widget.club.name,
                color: ClubHomeColors.accent,
                imageUrl: widget.club.logoUrl,
                size: 32,
                fontSize: 13,
                shape: 'circle',
                profilePhotoFallbackId: authService.currentAdmin?.id,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('club-home-composer-field'),
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: _focusNode.hasFocus ? 6 : 1,
                  onTapOutside: (_) => _focusNode.unfocus(),
                  onChanged: (_) => setState(() {}),
                  cursorColor: ClubHomeColors.text,
                  style: figtree(
                    size: 15,
                    weight: FontWeight.w500,
                    color: ClubHomeColors.text,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 5),
                    hintText: S.clubHomeComposerHint,
                    hintStyle: figtree(
                      size: 15,
                      weight: FontWeight.w500,
                      color: ClubHomeColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                key: const ValueKey('club-home-composer-photo'),
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(_pickPhoto()),
                child: _imagePath == null
                    ? SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: _pickingPhoto
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ClubHomeColors.muted,
                                  ),
                                )
                              : Icon(
                                  Icons.image_outlined,
                                  size: 19,
                                  color: ClubHomeColors.muted,
                                  semanticLabel: AppLocalizations.of(
                                    context,
                                  )!.addPhoto,
                                ),
                        ),
                      )
                    : Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            key: const ValueKey('club-home-composer-thumbnail'),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(7),
                            ),
                            child: Image.file(
                              File(_imagePath!),
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: -7,
                            right: -7,
                            child: GestureDetector(
                              key: const ValueKey(
                                'club-home-composer-remove-photo',
                              ),
                              behavior: HitTestBehavior.opaque,
                              onTap: _removePhoto,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: ClubHomeColors.card,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: ClubHomeColors.border,
                                  ),
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: ClubHomeColors.text,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const Spacer(),
              GestureDetector(
                key: const ValueKey('club-home-composer-post'),
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(_reviewPost()),
                child: SizedBox(
                  height: 32,
                  width: 48,
                  child: Center(
                    child: _posting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ClubHomeColors.accent,
                            ),
                          )
                        : Text(
                            S.post,
                            style: figtree(
                              size: 12,
                              weight: FontWeight.w700,
                              color: ClubHomeColors.accent,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── post card ────────────────────────────────────────────────────────────────

/// Final, non-publishing review step. Returning `true` is the only path that
/// lets the inline composer call Supabase and add the post to the feed.
class _ClubHomePostPreviewDialog extends StatelessWidget {
  const _ClubHomePostPreviewDialog({
    required this.club,
    required this.content,
    required this.imagePath,
  });

  final Club club;
  final String content;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    return Dialog(
      key: const ValueKey('club-home-post-preview'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      backgroundColor: ClubUpColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.readyToPost,
                    style: figtree(
                      size: 18,
                      weight: FontWeight.w800,
                      color: ClubUpColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppLocalizations.of(context)!.feedPreviewHint,
                    style: figtree(
                      size: 12,
                      weight: FontWeight.w500,
                      color: ClubUpColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: ClubUpColors.background,
                    border: Border.all(color: ClubUpColors.border),
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasImage)
                        buildPostBanner(
                          imagePath: imagePath,
                          fallbackColor: ClubHomeColors.accent,
                          fallbackLetter: club.name.isEmpty
                              ? '?'
                              : club.name[0],
                          height: 190,
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClubAvatar(
                                  clubId: club.id,
                                  clubName: club.name,
                                  color: ClubHomeColors.accent,
                                  imageUrl: club.logoUrl,
                                  size: 30,
                                  fontSize: 12,
                                  shape: 'circle',
                                  profilePhotoFallbackId:
                                      authService.currentAdmin?.id,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        club.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: figtree(
                                          size: 13,
                                          weight: FontWeight.w700,
                                          color: ClubUpColors.text,
                                        ),
                                      ),
                                      Text(
                                        AppLocalizations.of(context)!.justNow,
                                        style: figtree(
                                          size: 10,
                                          weight: FontWeight.w500,
                                          color: ClubUpColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (content.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                content,
                                style: figtree(
                                  size: 14,
                                  weight: FontWeight.w400,
                                  color: ClubUpColors.text,
                                  height: 1.4,
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('club-home-post-preview-back'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(AppLocalizations.of(context)!.back),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    key: const ValueKey('club-home-post-preview-confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ClubHomeColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(AppLocalizations.of(context)!.confirm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `design-society-post` `272:60` / `tech-connect-post` `272:119` — a rounded
/// card whose photo carries the club attribution as a floating badge, with the
/// caption and the interaction row in the body below.
class ClubHomeFeedPostCard extends StatefulWidget {
  const ClubHomeFeedPostCard({
    super.key,
    required this.post,
    required this.onChanged,
  });

  final NewsPost post;
  final VoidCallback onChanged;

  @override
  State<ClubHomeFeedPostCard> createState() => _ClubHomeFeedPostCardState();
}

class _ClubHomeFeedPostCardState extends State<ClubHomeFeedPostCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heart;
  late final Animation<double> _likeButtonScale;
  bool _burst = false;
  double _aspectRatio = 1;
  String? _probedPath;

  @override
  void initState() {
    super.initState();
    _heart =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          if (mounted && _burst) setState(() => _burst = false);
          _heart.reset();
        });
    _likeButtonScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.28), weight: 34),
      TweenSequenceItem(tween: Tween(begin: 1.28, end: 0.94), weight: 28),
      TweenSequenceItem(tween: Tween(begin: 0.94, end: 1), weight: 38),
    ]).animate(CurvedAnimation(parent: _heart, curve: Curves.easeOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final viewerId =
          authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
      viewTracker.recordView(widget.post.id, viewerId, syncRemote: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _probeAspectRatio();
  }

  @override
  void didUpdateWidget(covariant ClubHomeFeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.imagePath == widget.post.imagePath) return;
    _probedPath = null;
    _aspectRatio = 1;
    _probeAspectRatio();
  }

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _probeAspectRatio() {
    final path = widget.post.imagePath?.trim() ?? '';
    if (_probedPath == path) return;
    _probedPath = path;
    if (path.isEmpty || path.startsWith('http')) {
      _aspectRatio = 1;
      return;
    }
    if (path.startsWith('tpl:')) {
      _aspectRatio = kHomePostPortraitAspectRatio;
      return;
    }
    _aspectRatio = imageAspectRatioFromFile(File(path)) ?? 1;
  }

  void _onAspectRatio(double ratio) {
    if (!mounted || !ratio.isFinite || ratio <= 0) return;
    if ((_aspectRatio - ratio).abs() <= 0.001) return;
    setState(() => _aspectRatio = ratio);
  }

  String _timeAgo(DateTime dt) {
    final l10n = AppLocalizations.of(context)!;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inMinutes < 60) return l10n.minutesAgoSuffix(diff.inMinutes);
    if (diff.inHours < 24) return l10n.hoursAgoSuffix(diff.inHours);
    return l10n.daysAgoSuffix(diff.inDays);
  }

  void _openClub() {
    final club = clubForId(widget.post.clubId);
    if (club == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ClubProfileScreen(club: club, color: ClubHomeColors.accent),
      ),
    );
  }

  void _toggleLike() {
    final becomingLiked = !userState.isLiked(widget.post.id);
    unawaited(togglePostLike(widget.post.id));
    HapticFeedback.selectionClick();
    if (becomingLiked && !MediaQuery.disableAnimationsOf(context)) {
      _heart.forward(from: 0);
    }
    setState(() {});
    widget.onChanged();
  }

  void _doubleTapLike() {
    if (!_hasStudentIdentity) return;
    unawaited(ensurePostLiked(widget.post.id));
    HapticFeedback.mediumImpact();
    setState(() => _burst = true);
    _heart.forward(from: 0);
    widget.onChanged();
  }

  /// Liking, sharing and commenting all write against a student profile id.
  /// A club-admin login has none — a student acting as their club does.
  bool get _hasStudentIdentity => authService.currentUser != null;

  void _openComments() {
    showHomeCommentsSheet(
      context,
      post: widget.post,
      onChanged: () {
        if (mounted) setState(() {});
        widget.onChanged();
      },
    );
  }

  void _openShare() {
    showHomeShareSheet(
      context,
      post: widget.post,
      onChanged: () {
        if (mounted) setState(() {});
        widget.onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final club = clubForId(widget.post.clubId);
    if (club == null) return const SizedBox.shrink();
    final hasImage =
        widget.post.imagePath != null &&
        widget.post.imagePath!.trim().isNotEmpty;
    final body = widget.post.content.trim();

    return Container(
      key: ValueKey('club-home-post-card-${widget.post.id}'),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: ClubHomeColors.card,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        boxShadow: ClubHomeColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No frame in this section draws a text-only post, but the app has
          // them (announcements, polls). They keep the same attribution, moved
          // out of the photo it would otherwise float on.
          if (hasImage)
            _media(club.name)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _clubBadge(club.name, floating: false),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.post.isAnnouncement) ...[
                  _announcementChip(),
                  const SizedBox(height: 12),
                ],
                if (audienceForPost(widget.post) !=
                    ContentAudience.everyone) ...[
                  ContentAudiencePill(
                    key: ValueKey('content-audience-pill-${widget.post.id}'),
                    audience: audienceForPost(widget.post),
                    accent: ClubHomeColors.accent,
                  ),
                  const SizedBox(height: 12),
                ],
                if (body.isNotEmpty)
                  ExpandablePostCaption(
                    key: ValueKey('club-home-post-caption-${widget.post.id}'),
                    authorName: '',
                    caption: body,
                    collapsedWordCount: 45,
                    captionStyle: figtree(
                      size: 14,
                      weight: FontWeight.w400,
                      color: ClubHomeColors.text,
                      height: 1.4,
                    ),
                    moreStyle: figtree(
                      size: 14,
                      weight: FontWeight.w600,
                      color: ClubHomeColors.accent,
                    ),
                  ),
                if (widget.post.poll != null) ...[
                  const SizedBox(height: 12),
                  PollCard(post: widget.post, accent: ClubHomeColors.accent),
                ],
                if (body.isNotEmpty || widget.post.poll != null)
                  const SizedBox(height: 14),
                _interactionRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `image-viewport` `272:61` with `floating-club-badge` `272:63` over it.
  Widget _media(String clubName) {
    final height = homePostMediaHeight(
      MediaQuery.sizeOf(context).width,
      aspectRatio: _aspectRatio,
    );
    return GestureDetector(
      key: ValueKey('club-home-post-photo-${widget.post.id}'),
      onDoubleTap: _doubleTapLike,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            buildPostBanner(
              imagePath: widget.post.imagePath,
              fallbackColor: ClubHomeColors.accent,
              fallbackLetter: clubName.isEmpty ? '?' : clubName[0],
              height: height,
              onAspectRatio: _onAspectRatio,
            ),
            if (_burst)
              Center(
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.5, end: 1.4).animate(
                    CurvedAnimation(parent: _heart, curve: Curves.elasticOut),
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: Colors.white,
                    size: 72,
                  ),
                ),
              ),
            Positioned(
              left: 14,
              bottom: 14,
              child: _clubBadge(clubName, floating: true),
            ),
          ],
        ),
      ),
    );
  }

  /// `floating-club-badge` — avatar, club name, relative time.
  Widget _clubBadge(String clubName, {required bool floating}) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClubAvatar(
          clubId: widget.post.clubId,
          clubName: clubName,
          color: ClubHomeColors.accent,
          imageUrl: clubForId(widget.post.clubId)?.logoUrl,
          size: 24,
          fontSize: 10,
          shape: 'circle',
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clubName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: figtree(
                  size: 12,
                  weight: FontWeight.w700,
                  color: ClubHomeColors.text,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _timeAgo(widget.post.createdAt),
                maxLines: 1,
                style: figtree(
                  size: 9,
                  weight: FontWeight.w500,
                  color: ClubHomeColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return GestureDetector(
      key: ValueKey('club-home-post-club-${widget.post.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: _openClub,
      child: floating
          ? ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: ClubHomeColors.badgeSurface,
                    borderRadius: const BorderRadius.all(Radius.circular(20)),
                    border: Border.all(color: ClubHomeColors.badgeBorder),
                  ),
                  child: content,
                ),
              ),
            )
          : content,
    );
  }

  /// The frame has no announcement state, but the app does; this keeps the
  /// megaphone distinction in the card's own language.
  Widget _announcementChip() {
    return Container(
      key: ValueKey('club-home-post-announcement-${widget.post.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ClubHomeColors.accent.withValues(alpha: 0.10),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.campaign_rounded,
            size: 14,
            color: ClubHomeColors.accent,
          ),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context)!.announcement,
            style: figtree(
              size: 11,
              weight: FontWeight.w700,
              color: ClubHomeColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  /// `interaction-row` `272:72` — likes, comments and views over a hairline,
  /// the share plane on the right.
  Widget _interactionRow() {
    return Container(
      key: ValueKey('club-home-post-actions-${widget.post.id}'),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ClubHomeColors.border)),
      ),
      child: Row(
        children: [
          ListenableBuilder(
            listenable: userState,
            builder: (context, _) {
              final liked = userState.isLiked(widget.post.id);
              return _ClubHomePostAction(
                key: ValueKey('club-home-post-like-${widget.post.id}'),
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: '${postLikeCount(widget.post.id)}',
                color: liked ? ClubHomeColors.accent : ClubHomeColors.muted,
                iconScale: _likeButtonScale,
                // Likes belong to a student id; a club-admin login has none,
                // so the count reads but does not toggle.
                onTap: _hasStudentIdentity ? _toggleLike : null,
              );
            },
          ),
          const SizedBox(width: 18),
          ListenableBuilder(
            listenable: commentStore,
            builder: (context, _) => _ClubHomePostAction(
              key: ValueKey('club-home-post-comment-${widget.post.id}'),
              icon: Icons.chat_bubble_outline_rounded,
              label: '${commentStore.countFor(widget.post.id)}',
              color: ClubHomeColors.muted,
              onTap: _openComments,
            ),
          ),
          const SizedBox(width: 18),
          ListenableBuilder(
            listenable: viewTracker,
            builder: (context, _) => _ClubHomePostAction(
              key: ValueKey('club-home-post-views-${widget.post.id}'),
              icon: Icons.visibility_outlined,
              label: formatClubHomeCount(viewTracker.viewCount(widget.post.id)),
              color: ClubHomeColors.muted,
            ),
          ),
          const Spacer(),
          // `share-action` — sharing a post lands it in a chat as the sender,
          // which a club-admin login cannot be. The frame's own first card
          // draws no share control either.
          if (_hasStudentIdentity)
            GestureDetector(
              key: ValueKey('club-home-post-share-${widget.post.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: _openShare,
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: Transform.rotate(
                    angle: -0.35,
                    child: Icon(
                      Icons.send_outlined,
                      size: 18,
                      color: ClubHomeColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The frame prints view counts as `2.4k`.
String formatClubHomeCount(int value) {
  if (value < 1000) return '$value';
  final thousands = value / 1000;
  if (thousands >= 10) return '${thousands.round()}k';
  return '${thousands.toStringAsFixed(1)}k';
}

/// `like-action` / `comment-action` / `views-action` — an 18pt icon with its
/// count beside it. Views have no tap target in the frame.
class _ClubHomePostAction extends StatelessWidget {
  const _ClubHomePostAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.iconScale,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Animation<double>? iconScale;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget iconWidget = Icon(icon, size: 18, color: color);
    if (iconScale != null) {
      iconWidget = ScaleTransition(
        scale: reduceMotion ? const AlwaysStoppedAnimation(1) : iconScale!,
        child: iconWidget,
      );
    }
    final row = Row(
      children: [
        iconWidget,
        const SizedBox(width: 6),
        Text(
          label,
          style: figtree(
            size: 11,
            weight: FontWeight.w600,
            color: ClubHomeColors.muted,
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

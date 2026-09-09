import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/content_audience.dart';
import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/account_switcher_service.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/club_admin_access.dart';
import '../services/club_notification_service.dart';
import '../services/content_safety_service.dart';
import '../services/content_store.dart';
import '../services/mock_data.dart';
import '../services/media_delivery_service.dart';
import '../services/rate_limit_error.dart';
import '../services/user_state.dart';
import '../services/supabase_post_service.dart';
import '../widgets/app_network_image.dart';
import '../widgets/content_audience_sheet.dart';
import '../widgets/content_image_uploader.dart';
import '../widgets/club_avatar.dart';
import '../widgets/pinch_zoom_image.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/mention_text_field.dart';

// ── Template definitions ─────────────────────────────────────────────────────

class PostTemplate {
  final String id;
  final String label;
  final List<Color> colors;
  final Alignment begin;
  final Alignment end;

  const PostTemplate({
    required this.id,
    required this.label,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });
}

const _templates = [
  PostTemplate(
    id: 'tpl:0',
    label: 'Sunset',
    colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
  ),
  PostTemplate(
    id: 'tpl:1',
    label: 'Ocean',
    colors: [Color(0xFF667EEA), Color(0xFF64D9E8)],
  ),
  PostTemplate(
    id: 'tpl:2',
    label: 'Forest',
    colors: [Color(0xFF2E7D32), Color(0xFF81C784)],
  ),
  PostTemplate(
    id: 'tpl:3',
    label: 'Midnight',
    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
  ),
  PostTemplate(
    id: 'tpl:4',
    label: 'Rose',
    colors: [Color(0xFF8C1D40), Color(0xFFE91E8C)],
  ),
  PostTemplate(
    id: 'tpl:5',
    label: 'Gold',
    colors: [Color(0xFFB8860B), Color(0xFFFFD700)],
  ),
  PostTemplate(
    id: 'tpl:6',
    label: 'Aurora',
    colors: [Color(0xFF6A1B9A), Color(0xFF00BCD4)],
  ),
  PostTemplate(
    id: 'tpl:7',
    label: 'Lava',
    colors: [Color(0xFFE65100), Color(0xFFFF8F00)],
  ),
];

Widget buildPostBanner({
  required String? imagePath,
  required Color fallbackColor,
  required String fallbackLetter,
  double height = 200,
  MediaRendition rendition = MediaRendition.feed,
  ValueChanged<double>? onAspectRatio,
}) {
  // Network image (Supabase / Picsum / any remote URL)
  if (imagePath != null &&
      (imagePath.startsWith('https://') || imagePath.startsWith('http://'))) {
    return _ZoomablePostImage(
      height: height,
      child: AppNetworkImage(
        url: imagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: height,
        // Banners span device width but rarely need more than this to look
        // sharp, even on high-density screens — avoids decoding the full
        // up-to-3840px upload for what's usually a ~200-400dp-tall card.
        cacheWidth: rendition == MediaRendition.screen ? 800 : 500,
        rendition: rendition,
        preserveSourceAspectRatio: onAspectRatio != null,
        onAspectRatio: onAspectRatio,
        placeholderBuilder: (_) => SkeletonBox(
          width: double.infinity,
          height: height,
          borderRadius: BorderRadius.zero,
        ),
        errorBuilder: (ctx) => Container(
          width: double.infinity,
          height: height,
          color: Color.lerp(
            AppColors.surfaceAlt,
            fallbackColor.withValues(alpha: 0.18),
            0.35,
          ),
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: AppColors.secondaryText.withValues(alpha: 0.45),
              size: 34,
            ),
          ),
        ),
      ),
    );
  }

  // Gallery photo — tap to open full-screen (pinch/pan/double-tap zoom).
  if (imagePath != null && !imagePath.startsWith('tpl:')) {
    return _ZoomablePostImage(
      height: height,
      child: Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: height,
      ),
    );
  }

  // Template or fallback gradient
  final gradient = imagePath != null
      ? LinearGradient(
          colors: _templates
              .firstWhere((t) => t.id == imagePath, orElse: () => _templates[0])
              .colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : LinearGradient(
          colors: [
            fallbackColor.withValues(alpha: 0.7),
            fallbackColor.withValues(alpha: 0.25),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  return Container(
    width: double.infinity,
    height: height,
    decoration: BoxDecoration(gradient: gradient),
    child: Center(
      child: Text(
        fallbackLetter,
        style: TextStyle(
          fontSize: 72,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
    ),
  );
}

class _ZoomablePostImage extends StatelessWidget {
  final double height;
  final Widget child;

  const _ZoomablePostImage({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    return PinchZoomImage(
      child: SizedBox(width: double.infinity, height: height, child: child),
    );
  }
}

// ── Create Post Screen ───────────────────────────────────────────────────────

class CreatePostScreen extends StatefulWidget {
  final VoidCallback? onPosted;
  final bool startWithPhotoUpload;

  const CreatePostScreen({
    super.key,
    this.onPosted,
    this.startWithPhotoUpload = false,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final String _reservedPostId = const Uuid().v4();

  bool _isPosting = false;

  _ClubOption? _selectedClub;
  late final List<_ClubOption> _myClubs;
  final Set<String> _selectedTaggedClubIds = {};
  final Set<String> _selectedTaggedUserIds = {};

  /// Who the post is addressed to — `everyone` unless the club narrows it.
  ContentAudience _selectedAudience = ContentAudience.everyone;

  // Image state
  String? _imagePath;

  bool get _hasUploadedPhoto =>
      _imagePath != null &&
      _imagePath!.isNotEmpty &&
      !_imagePath!.startsWith('tpl:');

  @override
  void initState() {
    super.initState();
    final adminId = authService.currentAdmin?.id ?? '';
    final linkedClub = accountSwitcherService.activeClub;
    _myClubs =
        (linkedClub != null
                ? [linkedClub]
                : clubs.where((c) => clubIsManagedByAdmin(c, adminId)))
            .map((c) => _ClubOption(id: c.id, name: c.name))
            .toList();
    if (_myClubs.length == 1) _selectedClub = _myClubs.first;
  }

  Future<void> _pickAudience() async {
    final picked = await showContentAudienceSheet(
      context,
      current: _selectedAudience,
      surface: AppColors.card,
      border: AppColors.divider,
      text: AppColors.text,
      muted: AppColors.secondaryText,
      accent: AppColors.primaryRed,
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedAudience = picked);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  String _mentionKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  bool _containsMention(String content, String label) {
    final lower = content.toLowerCase();
    final firstWordMention = '@${label.split(' ').first.toLowerCase()}';
    final fullNameMention = '@${label.toLowerCase()}';
    final compactContent = _mentionKey(content);
    final compactMention = _mentionKey('@$label');
    return lower.contains(firstWordMention) ||
        lower.contains(fullNameMention) ||
        compactContent.contains(compactMention);
  }

  List<String> _extractTaggedClubIds(String content) {
    final tagged = <String>{..._selectedTaggedClubIds};
    final lower = content.toLowerCase();
    for (final club in clubs) {
      if (club.id == _selectedClub?.id) continue;
      if (_containsMention(lower, club.name)) {
        tagged.add(club.id);
      }
    }
    return tagged.toList();
  }

  List<String> _extractTaggedUserIds(String content) {
    final tagged = <String>{..._selectedTaggedUserIds};
    for (final user in users) {
      if (_containsMention(content, user.name)) {
        tagged.add(user.id);
      }
    }
    return tagged.toList();
  }

  void _rememberMention(MentionOption option) {
    if (option.type == MentionType.club) {
      if (option.id != _selectedClub?.id) {
        _selectedTaggedClubIds.add(option.id);
      }
    } else {
      _selectedTaggedUserIds.add(option.id);
    }
  }

  List<MentionOption> get _mentionOptions => [
    ...clubs.map(
      (club) =>
          MentionOption(id: club.id, label: club.name, type: MentionType.club),
    ),
    ...users.map(
      (user) => MentionOption(
        id: user.id,
        label: userState.displayNameFor(user.id, user.name),
        type: MentionType.student,
      ),
    ),
  ];

  Future<void> _post() async {
    final content = _contentController.text.trim();
    if (content.isEmpty || _selectedClub == null) return;
    setState(() => _isPosting = true);

    try {
      final post = await supabasePostService.createPost(
        reservedPostId: _reservedPostId,
        clubId: _selectedClub!.id,
        authorId: accountSwitcherService.actorId,
        content: content,
        taggedClubIds: _extractTaggedClubIds(content),
        taggedUserIds: _extractTaggedUserIds(content),
        imagePath: _hasUploadedPhoto ? _imagePath : null,
        audience: _selectedAudience,
      );
      if (!mounted) return;
      newsPosts.insert(0, post);
      unawaited(contentStore.saveNewsPosts());
      contentStore.notifyContentChanged();
      if (!supabasePostService.isAvailable) {
        unawaited(clubNotificationService.notifyFollowersAboutPost(post));
        clubNotificationService.notifyMentionedUsers(post);
      }
      widget.onPosted?.call();
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Create post failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_publishErrorMessage(context, error)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  String _publishErrorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is ContentSafetyException) return error.message;
    final limited = RateLimitInfo.from(error);
    if (limited != null) return limited.displayMessage;
    final text = error.toString();
    if (text.contains('row-level security') ||
        text.contains('permission denied') ||
        text.contains('42501')) {
      return l10n.publishErrorRlsPolicy;
    }
    if (text.contains('image_path') || text.contains('column')) {
      return l10n.publishErrorMigration;
    }
    if (text.contains('post-images') || text.contains('storage')) {
      return l10n.publishErrorStorage;
    }
    return l10n.publishErrorGeneric;
  }

  bool get _canPost =>
      _contentController.text.trim().isNotEmpty && _selectedClub != null;

  @override
  Widget build(BuildContext context) {
    final adminName =
        authService.currentAdmin?.name ??
        AppLocalizations.of(context)!.clubFallbackName;
    dynamic selectedClubModel;
    if (_selectedClub != null) {
      for (final c in clubs) {
        if (c.id == _selectedClub!.id) {
          selectedClubModel = c;
          break;
        }
      }
    }
    final clubName = _selectedClub?.name ?? adminName;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            AppLocalizations.of(context)!.cancel,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ),
        leadingWidth: 84,
        title: Text(
          AppLocalizations.of(context)!.newPostTitle,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedOpacity(
              opacity: _canPost ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 150),
              child: ElevatedButton(
                onPressed: _canPost && !_isPosting ? () => _post() : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: _isPosting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        AppLocalizations.of(context)!.post,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Form fields ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Who is posting — club avatar + name
                Row(
                  children: [
                    ClubAvatar(
                      clubId: _selectedClub?.id ?? '',
                      clubName: clubName,
                      color: AppColors.primaryRed,
                      size: 46,
                      fontSize: 18,
                      imageUrl: selectedClubModel?.logoUrl as String?,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clubName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.postingAsClub(clubName),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Club picker
                if (_myClubs.length > 1) ...[
                  Text(
                    AppLocalizations.of(context)!.postingAsLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      border: Border.all(color: AppColors.divider),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<_ClubOption>(
                        value: _selectedClub,
                        isExpanded: true,
                        hint: Text(
                          AppLocalizations.of(context)!.selectClubHint,
                          style: TextStyle(color: AppColors.secondaryText),
                        ),
                        dropdownColor: AppColors.card,
                        items: _myClubs
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedClub = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Audience — sits with "who am I posting as", because "who is
                // this for" is the same kind of decision. Same label-row idiom
                // as the photo section further down.
                Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: AppColors.text,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      S.audienceFieldLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  key: const ValueKey('create-post-audience'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_pickAudience()),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            S.audienceTierLabel(_selectedAudience),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: AppColors.secondaryText,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Content — blends into the active light/dark page surface
                Container(
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
                  color: AppColors.background,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MentionTextField(
                        controller: _contentController,
                        options: _mentionOptions,
                        onMentionSelected: _rememberMention,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.text,
                          height: 1.6,
                        ),
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(
                            context,
                          )!.writeForClubMembersHint,
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: AppColors.secondaryText,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isCollapsed: true,
                        ),
                        maxLines: null,
                        minLines: 5,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(500),
                        ],
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 10),
                      Divider(height: 1, color: AppColors.divider),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.alternate_email,
                            size: 14,
                            color: AppColors.secondaryText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppLocalizations.of(context)!.typeAtToTagHint,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryText,
                            ),
                          ),
                          const Spacer(),
                          Builder(
                            builder: (_) {
                              final len = _contentController.text.length;
                              final isLow = 500 - len <= 40;
                              return Text(
                                '$len/500',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isLow
                                      ? Colors.red
                                      : AppColors.secondaryText,
                                  fontWeight: isLow
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Photo
                Row(
                  children: [
                    Icon(Icons.image_outlined, size: 16, color: AppColors.text),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(context)!.photoLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ContentImageUploader(
                  imagePath: _imagePath,
                  onChanged: (path) => setState(() => _imagePath = path),
                  height: 200,
                  compact: true,
                  emptyTitle: AppLocalizations.of(context)!.addAPhotoTitle,
                  emptySubtitle: AppLocalizations.of(
                    context,
                  )!.tapToPickFromCameraOrLibrary,
                ),
                const SizedBox(height: 20),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Club option ───────────────────────────────────────────────────────────────

class _ClubOption {
  final String id;
  final String name;
  const _ClubOption({required this.id, required this.name});

  @override
  bool operator ==(Object other) => other is _ClubOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

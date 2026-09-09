import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/content_audience.dart';
import '../models/news_post.dart';
import '../services/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../services/content_store.dart';
import '../services/content_visibility.dart';
import '../services/image_aspect_ratio.dart';
import '../services/mock_data.dart';
import '../services/moderation_service.dart';
import '../services/media_delivery_service.dart';
import '../services/post_like_helper.dart';
import '../services/supabase_post_service.dart';
import '../services/user_state.dart';
import '../widgets/club_avatar.dart';
import '../widgets/content_audience_sheet.dart';
import '../widgets/moderation_reason_sheet.dart';
import '../widgets/poll_card.dart';
import 'create_post_screen.dart' show buildPostBanner;

class PostDetailScreen extends StatefulWidget {
  final NewsPost post;
  final Color clubColor;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.clubColor,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  double _imageAspectRatio = 1;
  String? _probedImagePath;

  String get _currentAdminId => authService.currentAdmin?.id ?? '';

  bool get _canDeletePost =>
      contentStore.canDeletePost(widget.post.id, _currentAdminId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _probeImageAspectRatio();
  }

  @override
  void didUpdateWidget(covariant PostDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.imagePath == widget.post.imagePath) return;
    _probedImagePath = null;
    _imageAspectRatio = 1;
    _probeImageAspectRatio();
  }

  void _probeImageAspectRatio() {
    final path = widget.post.imagePath?.trim() ?? '';
    if (_probedImagePath == path) return;
    _probedImagePath = path;
    if (path.isEmpty) {
      _imageAspectRatio = 1;
      return;
    }
    if (path.startsWith('tpl:')) {
      _imageAspectRatio = kHomePostPortraitAspectRatio;
      return;
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      _imageAspectRatio = 1;
      return;
    }
    _imageAspectRatio = imageAspectRatioFromFile(File(path)) ?? 1;
  }

  void _onImageAspectRatio(double ratio) {
    if (!mounted || !ratio.isFinite || ratio <= 0) return;
    if ((_imageAspectRatio - ratio).abs() <= 0.001) return;
    setState(() => _imageAspectRatio = ratio);
  }

  Widget _postImage(String clubName) {
    final safeRatio = _imageAspectRatio.isFinite && _imageAspectRatio > 0
        ? _imageAspectRatio
        : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = homePostMediaHeight(
          MediaQuery.sizeOf(context).width,
          aspectRatio: safeRatio,
        );
        return SizedBox(
          key: ValueKey('post-detail-photo-${widget.post.id}'),
          width: width,
          height: height,
          child: buildPostBanner(
            imagePath: widget.post.imagePath,
            fallbackColor: widget.clubColor,
            fallbackLetter: clubName.isEmpty ? '?' : clubName[0],
            height: height,
            rendition: MediaRendition.screen,
            onAspectRatio: _onImageAspectRatio,
          ),
        );
      },
    );
  }

  void _confirmDelete() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: Text(
          AppLocalizations.of(context)!.deletePost,
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text),
        ),
        content: Text(
          AppLocalizations.of(context)!.deletePostMsg,
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true || !mounted) return;
      try {
        await supabasePostService.deletePost(widget.post);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.couldNotDeletePostSupabase,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
      final ok = contentStore.deletePost(widget.post.id, _currentAdminId);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
      } else {
        Navigator.popUntil(context, (r) => r.isFirst);
      }
    });
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return AppLocalizations.of(context)!.justNow;
    if (diff.inMinutes < 60) {
      return AppLocalizations.of(context)!.minutesAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) {
      return AppLocalizations.of(context)!.hoursAgo(diff.inHours);
    }
    if (diff.inDays == 1) return AppLocalizations.of(context)!.yesterday;
    if (diff.inDays < 7) {
      return AppLocalizations.of(context)!.daysAgo(diff.inDays);
    }
    return '${DateFormat.MMM(localeService.languageCode).format(dt)} ${dt.day}';
  }

  void _toggleLike() {
    if (!authService.isStudentSession) return;
    togglePostLike(widget.post.id);
    setState(() {});
  }

  Future<void> _reportPost() async {
    final reason = await showModerationReasonSheet(
      context,
      title: AppLocalizations.of(context)!.whyReportPost,
    );
    if (reason == null || !mounted) return;

    var delivered = true;
    try {
      await moderationService.reportPost(widget.post, reason: reason);
    } catch (_) {
      delivered = false;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.maybePop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            delivered
                ? AppLocalizations.of(context)!.postReportedAndRemoved
                : AppLocalizations.of(context)!.postHiddenOffline,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final club = clubs.firstWhere((c) => c.id == widget.post.clubId);
    final isStudent = authService.isStudentSession;
    final isLiked = userState.isLiked(widget.post.id);
    final likeCount = postLikeCount(widget.post.id);
    final hasImage =
        widget.post.imagePath != null && widget.post.imagePath!.isNotEmpty;
    final audience = audienceForPost(widget.post);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        title: Text(
          club.name,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (isStudent)
            IconButton(
              tooltip: AppLocalizations.of(context)!.reportPost,
              icon: Icon(Icons.flag_outlined, color: AppColors.secondaryText),
              onPressed: _reportPost,
            ),
          if (_canDeletePost)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Club header ──
                  Container(
                    color: AppColors.card,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClubAvatar(
                              clubId: club.id,
                              clubName: club.name,
                              size: 42,
                              fontSize: 18,
                              color: widget.clubColor,
                              imageUrl: club.logoUrl,
                              shape: 'circle',
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    club.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  Text(
                                    _timeAgo(widget.post.createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Restricted content says so on its own page too, not
                        // only on the card that led here.
                        if (audience != ContentAudience.everyone) ...[
                          const SizedBox(height: 10),
                          ContentAudiencePill(
                            key: ValueKey(
                              'content-audience-pill-${widget.post.id}',
                            ),
                            audience: audience,
                            accent: widget.clubColor,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Banner image ──
                  if (hasImage) _postImage(club.name),

                  // ── Like count ──
                  Container(
                    color: AppColors.card,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: isStudent ? _toggleLike : null,
                          child: Row(
                            children: [
                              Icon(
                                isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isLiked
                                    ? Colors.pink
                                    : AppColors.secondaryText,
                                size: 22,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$likeCount',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Full content ──
                  Container(
                    color: AppColors.card,
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.post.content,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.text,
                            height: 1.6,
                          ),
                        ),
                        if (widget.post.poll != null)
                          PollCard(post: widget.post, accent: widget.clubColor),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

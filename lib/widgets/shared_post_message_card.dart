import 'package:flutter/material.dart';

import '../models/content_audience.dart';
import '../models/news_post.dart';
import '../screens/create_post_screen.dart' show buildPostBanner;
import '../screens/post_detail_screen.dart';
import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/content_visibility.dart';
import '../services/mock_data.dart';
import 'club_avatar.dart';
import 'content_audience_sheet.dart';

/// Compact, tappable post preview rendered inside conversations.
class SharedPostMessageCard extends StatelessWidget {
  const SharedPostMessageCard({
    super.key,
    required this.postId,
    this.onDarkBackground = false,
  });

  final String postId;
  final bool onDarkBackground;

  NewsPost? get _post {
    for (final post in newsPosts) {
      if (post.id == postId) return post;
    }
    return null;
  }

  static const List<Color> _colors = <Color>[
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  Color _clubColor(String clubId) {
    final ordinal = clubOrdinal(clubId);
    return _colors[(ordinal < 0 ? 0 : ordinal) % _colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    if (post == null) {
      return Container(
        key: ValueKey('shared-post-unavailable-$postId'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: onDarkBackground
              ? Colors.white.withValues(alpha: 0.14)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined, size: 20),
            const SizedBox(width: 8),
            Text(S.sharedPost),
          ],
        ),
      );
    }
    final club = clubForId(post.clubId);
    final color = _clubColor(post.clubId);
    final foreground = onDarkBackground ? Colors.white : AppColors.text;
    final secondary = onDarkBackground
        ? Colors.white70
        : AppColors.secondaryText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('shared-post-card-${post.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(post: post, clubColor: color),
          ),
        ),
        child: Container(
          width: 250,
          decoration: BoxDecoration(
            color: onDarkBackground
                ? Colors.white.withValues(alpha: 0.13)
                : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: onDarkBackground
                  ? Colors.white.withValues(alpha: 0.22)
                  : AppColors.divider,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((post.imagePath ?? '').isNotEmpty)
                SizedBox(
                  height: 112,
                  width: double.infinity,
                  child: buildPostBanner(
                    imagePath: post.imagePath,
                    fallbackColor: color,
                    fallbackLetter: (club?.name.isNotEmpty ?? false)
                        ? club!.name[0]
                        : 'C',
                    height: 112,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClubAvatar(
                          clubId: club?.id ?? post.clubId,
                          clubName: club?.name ?? '',
                          color: color,
                          imageUrl: club?.logoUrl,
                          size: 24,
                          fontSize: 10,
                          shape: 'circle',
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            club?.name ?? S.sharedPost,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (post.content.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        post.content.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondary,
                          height: 1.3,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    // A restricted post keeps its badge when it is forwarded
                    // into a conversation — that is where the recipient is
                    // least likely to know where it came from.
                    if (audienceForPost(post) != ContentAudience.everyone) ...[
                      const SizedBox(height: 8),
                      ContentAudiencePill(
                        key: ValueKey('content-audience-pill-${post.id}'),
                        audience: audienceForPost(post),
                        accent: onDarkBackground ? Colors.white : color,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

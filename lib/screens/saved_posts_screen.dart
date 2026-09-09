import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/club.dart';
import '../models/content_audience.dart';
import '../models/event.dart';
import '../models/news_post.dart';
import '../services/app_colors.dart';
import '../services/locale_service.dart';
import '../services/mock_data.dart';
import '../services/auth_service.dart';
import '../services/user_prefs_service.dart';
import '../services/user_state.dart';
import '../widgets/club_avatar.dart';
import '../widgets/content_audience_sheet.dart';
import 'event_detail_screen.dart';
import 'post_detail_screen.dart';
import '../services/content_visibility.dart';

/// Lists everything the current user has bookmarked via the save button —
/// posts and events, split by a segmented control. Tapping a row opens the
/// full post/event; the bookmark icon removes it.
class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  int _segment = 0; // 0 = posts, 1 = events

  static const List<Color> _clubColors = [
    Color(0xFF8C1D40),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  Color _clubColor(String clubId) {
    final idx = clubOrdinal(clubId);
    return _clubColors[(idx < 0 ? 0 : idx) % _clubColors.length];
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays >= 7) return '${diff.inDays ~/ 7}w';
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'now';
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = authService.isStudentSession;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.savedTitle),
        backgroundColor: AppColors.card,
      ),
      body: ListenableBuilder(
        listenable: userState,
        builder: (context, _) {
          if (!isStudent) {
            return Center(
              child: Text(
                AppLocalizations.of(context)!.savedPostsStudentsOnly,
                style: TextStyle(color: AppColors.secondaryText),
              ),
            );
          }

          // A student can have saved content *before* the club restricted it,
          // so this is the one surface where the tier changes under the viewer.
          final savedPosts =
              newsPosts
                  .where((p) => userState.isSaved(p.id) && canViewPost(p))
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final savedEvents =
              events
                  .where((e) => userState.isSaved(e.id) && canViewEvent(e))
                  .toList()
                ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _SegmentedBar(
                  segment: _segment,
                  postCount: savedPosts.length,
                  eventCount: savedEvents.length,
                  onChanged: (i) => setState(() => _segment = i),
                ),
              ),
              Expanded(
                child: _segment == 0
                    ? _buildPostsList(savedPosts)
                    : _buildEventsList(savedEvents),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty(String title, String hint) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmark_border_rounded,
            size: 56,
            color: AppColors.secondaryText,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
          ),
        ],
      ),
    );
  }

  void _removeSaved(String id) {
    userState.toggleSave(id);
    userPrefsService.save(
      authService.isStudentSession ? authService.currentUser?.id ?? '' : '',
    );
  }

  Widget _buildPostsList(List<NewsPost> saved) {
    if (saved.isEmpty) {
      return _buildEmpty(
        AppLocalizations.of(context)!.noSavedPostsYet,
        AppLocalizations.of(context)!.tapBookmarkPostHint,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: saved.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, index) {
        final post = saved[index];
        final club = clubs.cast<Club?>().firstWhere(
          (c) => c?.id == post.clubId,
          orElse: () => null,
        );
        final color = _clubColor(post.clubId);
        return _SavedPostRow(
          post: post,
          club: club,
          color: color,
          timeAgo: _timeAgo(post.createdAt),
          onOpen: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostDetailScreen(post: post, clubColor: color),
            ),
          ),
          onRemove: () => _removeSaved(post.id),
        );
      },
    );
  }

  Widget _buildEventsList(List<Event> saved) {
    if (saved.isEmpty) {
      return _buildEmpty(
        AppLocalizations.of(context)!.noSavedEventsYet,
        AppLocalizations.of(context)!.tapBookmarkEventHint,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: saved.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, index) {
        final event = saved[index];
        final club = clubs.cast<Club?>().firstWhere(
          (c) => c?.id == event.clubId,
          orElse: () => null,
        );
        final color = _clubColor(event.clubId);
        return _SavedEventRow(
          event: event,
          club: club,
          color: color,
          onOpen: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventDetailScreen(event: event, color: color),
            ),
          ),
          onRemove: () => _removeSaved(event.id),
        );
      },
    );
  }
}

class _SegmentedBar extends StatelessWidget {
  final int segment;
  final int postCount;
  final int eventCount;
  final ValueChanged<int> onChanged;

  const _SegmentedBar({
    required this.segment,
    required this.postCount,
    required this.eventCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          _segmentButton(
            AppLocalizations.of(context)!.postsCountLabel(postCount),
            0,
          ),
          _segmentButton(
            AppLocalizations.of(context)!.eventsCountLabel(eventCount),
            1,
          ),
        ],
      ),
    );
  }

  Widget _segmentButton(String label, int index) {
    final selected = segment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.all(Radius.circular(999)),
            border: selected ? Border.all(color: AppColors.divider) : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.text : AppColors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedPostRow extends StatelessWidget {
  final NewsPost post;
  final Club? club;
  final Color color;
  final String timeAgo;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _SavedPostRow({
    required this.post,
    required this.club,
    required this.color,
    required this.timeAgo,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClubAvatar(
              clubId: club?.id ?? post.clubId,
              clubName:
                  club?.name ?? AppLocalizations.of(context)!.clubFallbackName,
              color: color,
              imageUrl: club?.logoUrl,
              size: 42,
              fontSize: 16,
              shape: 'circle',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          club?.name ??
                              AppLocalizations.of(context)!.campusPostFallback,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  if (audienceForPost(post) != ContentAudience.everyone) ...[
                    const SizedBox(height: 6),
                    ContentAudiencePill(
                      key: ValueKey('content-audience-pill-${post.id}'),
                      audience: audienceForPost(post),
                      accent: color,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.bookmark, color: color),
              tooltip: AppLocalizations.of(context)!.removeFromSaved,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedEventRow extends StatelessWidget {
  final Event event;
  final Club? club;
  final Color color;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _SavedEventRow({
    required this.event,
    required this.club,
    required this.color,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final date = event.dateTime;
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final isPast = event.endTime.isBefore(DateTime.now());

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date block
            Container(
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isPast ? 0.06 : 0.1),
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat.MMM(
                      localeService.languageCode,
                    ).format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: color,
                    ),
                  ),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${club?.name ?? AppLocalizations.of(context)!.campusEventFallback} · $time · ${event.location}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  if (audienceForEvent(event) != ContentAudience.everyone) ...[
                    const SizedBox(height: 6),
                    ContentAudiencePill(
                      key: ValueKey('content-audience-pill-${event.id}'),
                      audience: audienceForEvent(event),
                      accent: color,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.bookmark, color: color),
              tooltip: AppLocalizations.of(context)!.removeFromSaved,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

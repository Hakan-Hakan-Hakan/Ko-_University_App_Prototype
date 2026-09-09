import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/club.dart';
import '../models/event.dart';
import '../models/news_post.dart';
import '../services/app_colors.dart';
import '../services/auth_service.dart';
import '../services/club_insights_service.dart';
import '../services/content_store.dart';
import '../services/lazy_content_loader.dart';
import '../services/locale_service.dart';
import '../services/mock_clubup_profile.dart';
import '../services/mock_data.dart';
import '../services/people_service.dart';
import '../services/supabase_event_service.dart';
import '../services/supabase_post_service.dart';
import '../services/theme_service.dart';
import 'club_insights_screen.dart';
import 'event_detail_screen.dart';
import 'post_detail_screen.dart';
import 'settings_screen.dart';
import '../services/rsvp_store.dart';

/// App-wide moderation dashboard. The overview keeps campus totals and club
/// rankings, while the content tabs expose every loaded post and event to the
/// verified platform administrator.
class AdminDashboard extends StatefulWidget {
  final VoidCallback? onLogout;

  const AdminDashboard({super.key, this.onLogout});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const List<Color> _hues = [
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  final Set<String> _deletingPostIds = {};
  final Set<String> _deletingEventIds = {};
  int _peopleCount = 0;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    contentStore.addListener(_onContentChanged);
    themeService.addListener(_onThemeOrLocaleChanged);
    localeService.addListener(_onThemeOrLocaleChanged);
  }

  @override
  void dispose() {
    contentStore.removeListener(_onContentChanged);
    themeService.removeListener(_onThemeOrLocaleChanged);
    localeService.removeListener(_onThemeOrLocaleChanged);
    super.dispose();
  }

  void _onContentChanged() {
    if (mounted) setState(() {});
  }

  void _onThemeOrLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    try {
      await lazyContentLoader.ensureContentLoaded(force: true);
      final people = await peopleService.fetchPeople();
      if (!mounted) return;
      setState(() => _peopleCount = people.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _peopleCount = users.length);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Color _hueFor(Club club) {
    final idx = clubs.indexOf(club);
    return _hues[(idx < 0 ? 0 : idx) % _hues.length];
  }

  Club? _clubFor(String clubId) => clubForId(clubId);

  String _dateTime(DateTime value) =>
      DateFormat.yMMMd(localeService.languageCode).add_jm().format(value);

  // MainNavScreen's floating bottom navigation overlays this dashboard's
  // inner Scaffold, so keep enough room for the final row to scroll clear of
  // it on devices with and without a bottom safe-area inset.
  double get _bottomScrollInset =>
      128 + MediaQuery.of(context).padding.bottom;

  Future<void> _confirmAndLogout() async {
    if (widget.onLogout == null) return;
    if (!await showLogoutConfirmationDialog(context) || !mounted) return;
    await authService.logout();
    if (!mounted) return;
    // Matches SettingsScreen's logout: the RSVP cache is account-scoped and
    // would otherwise survive into the next session.
    rsvpStore.clear();
    widget.onLogout!();
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.card,
            title: Text(
              title,
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              message,
              style: TextStyle(color: AppColors.secondaryText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(AppLocalizations.of(context)!.delete),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deletePost(NewsPost post) async {
    final admin = authService.currentAdmin;
    if (!isClubUpAdmin(admin) || _deletingPostIds.contains(post.id)) return;
    final confirmed = await _confirmDelete(
      title: AppLocalizations.of(context)!.deletePost,
      message: AppLocalizations.of(context)!.deletePostMsg,
    );
    if (!confirmed || !mounted) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() => _deletingPostIds.add(post.id));
    try {
      await supabasePostService.deletePost(post);
      final removed = contentStore.deletePost(post.id, admin!.id);
      if (!removed) throw StateError('Post could not be removed locally.');
      _showMessage(l10n.postDeletedConfirmation);
    } catch (_) {
      _showMessage(l10n.couldNotDeletePostSupabase, isError: true);
    } finally {
      if (mounted) setState(() => _deletingPostIds.remove(post.id));
    }
  }

  Future<void> _deleteEvent(Event event) async {
    final admin = authService.currentAdmin;
    if (!isClubUpAdmin(admin) || _deletingEventIds.contains(event.id)) return;
    final confirmed = await _confirmDelete(
      title: AppLocalizations.of(context)!.deleteEvent,
      message: AppLocalizations.of(context)!.deleteEventMsg,
    );
    if (!confirmed || !mounted) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() => _deletingEventIds.add(event.id));
    try {
      await supabaseEventService.deleteEvent(event);
      final removed = contentStore.deleteEvent(event.id, admin!.id);
      if (!removed) throw StateError('Event could not be removed locally.');
      _showMessage(l10n.eventDeletedConfirmation);
    } catch (_) {
      _showMessage(l10n.couldNotDeleteEventSupabase, isError: true);
    } finally {
      if (mounted) setState(() => _deletingEventIds.remove(event.id));
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.text,
          surfaceTintColor: Colors.transparent,
          title: Text(
            l10n.adminDashboardTitle,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: l10n.logOut,
              onPressed: widget.onLogout == null ? null : _confirmAndLogout,
              icon: const Icon(Icons.logout_rounded),
            ),
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(right: 18),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
          bottom: TabBar(
            labelColor: AppColors.primaryRed,
            unselectedLabelColor: AppColors.secondaryText,
            indicatorColor: AppColors.primaryRed,
            tabs: [
              Tab(text: l10n.overview),
              Tab(text: l10n.allPosts),
              Tab(text: l10n.allEvents),
            ],
          ),
        ),
        body: TabBarView(children: [_overviewTab(), _postsTab(), _eventsTab()]),
      ),
    );
  }

  Widget _overviewTab() {
    final ranked = [...clubs];
    final stats = clubInsightsService.computeAll(ranked);
    ranked.sort((a, b) {
      final byFollowers = stats[b.id]!.followers.compareTo(
        stats[a.id]!.followers,
      );
      if (byFollowers != 0) return byFollowers;
      return stats[b.id]!.totalRsvps.compareTo(stats[a.id]!.totalRsvps);
    });
    final top = ranked.take(10).toList();
    final l10n = AppLocalizations.of(context)!;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 14, 16, _bottomScrollInset),
        children: [
          Row(
            children: [
              _tile(
                l10n.students,
                _peopleCount == 0 ? users.length : _peopleCount,
                Icons.school_outlined,
              ),
              const SizedBox(width: 10),
              _tile(l10n.clubs, clubs.length, Icons.groups_2_outlined),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _tile(l10n.events, events.length, Icons.event_outlined),
              const SizedBox(width: 10),
              _tile(l10n.posts, newsPosts.length, Icons.article_outlined),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            l10n.clubLeaderboard.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < top.length; i++)
            _leaderRow(rank: i + 1, club: top[i], stat: stats[top[i].id]!),
        ],
      ),
    );
  }

  Widget _postsTab() {
    final allPosts = [...newsPosts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (allPosts.isEmpty) {
      return _emptyTab(AppLocalizations.of(context)!.noPostsYet);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 12, 12, _bottomScrollInset),
        itemCount: allPosts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final post = allPosts[index];
          final club = _clubFor(post.clubId);
          final deleting = _deletingPostIds.contains(post.id);
          return Card(
            key: ValueKey<String>('admin-post-${post.id}'),
            color: AppColors.card,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              side: BorderSide(color: AppColors.divider),
            ),
            child: ListTile(
              onTap: club == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(
                          post: post,
                          clubColor: _hueFor(club),
                        ),
                      ),
                    ),
              title: Text(
                post.content.trim().isEmpty ? '—' : post.content.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${club?.name ?? post.clubId}  •  ${_dateTime(post.createdAt)}',
                maxLines: 2,
                style: TextStyle(color: AppColors.secondaryText),
              ),
              trailing: deleting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: ValueKey<String>('delete-admin-post-${post.id}'),
                      tooltip: AppLocalizations.of(context)!.deletePostAction,
                      onPressed: () => _deletePost(post),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _eventsTab() {
    final allEvents = [...events]
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    if (allEvents.isEmpty) {
      return _emptyTab(AppLocalizations.of(context)!.noEventsYet);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 12, 12, _bottomScrollInset),
        itemCount: allEvents.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final event = allEvents[index];
          final club = _clubFor(event.clubId);
          final deleting = _deletingEventIds.contains(event.id);
          final color = club == null ? AppColors.primaryRed : _hueFor(club);
          return Card(
            key: ValueKey<String>('admin-event-${event.id}'),
            color: AppColors.card,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              side: BorderSide(color: AppColors.divider),
            ),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EventDetailScreen(event: event, color: color),
                ),
              ),
              title: Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${club?.name ?? event.clubId}  •  ${_dateTime(event.dateTime)}\n${event.location}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.secondaryText),
              ),
              isThreeLine: true,
              trailing: deleting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: ValueKey<String>('delete-admin-event-${event.id}'),
                      tooltip: AppLocalizations.of(
                        context,
                      )!.deleteEventMenuItem,
                      onPressed: () => _deleteEvent(event),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyTab(String message) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: _bottomScrollInset),
        children: [
          SizedBox(
            height: 360,
            child: Center(
              child: Text(
                message,
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(String label, int value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.primaryRed),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leaderRow({
    required int rank,
    required Club club,
    required ClubInsightsData stat,
  }) {
    final color = _hueFor(club);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClubInsightsScreen(club: club, accent: color),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rank <= 3
                    ? AppColors.primaryRed.withValues(alpha: 0.14)
                    : AppColors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: rank <= 3
                      ? AppColors.primaryRed
                      : AppColors.secondaryText,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                club.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(
                context,
              )!.followersAndRsvpsSummary(stat.followers, stat.totalRsvps),
              style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

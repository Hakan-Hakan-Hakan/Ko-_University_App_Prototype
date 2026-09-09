import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/account_switcher_service.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/theme_service.dart';
import '../services/content_visibility.dart';
import '../services/content_store.dart';
import '../services/mock_data.dart';
import '../services/auth_service.dart';
import '../services/club_admin_access.dart';
import '../services/mock_clubup_profile.dart';
import '../services/feed_v2_controller.dart';
import '../services/feed_v2_service.dart';
import '../services/image_aspect_ratio.dart';
import '../services/moderation_service.dart';
import '../services/people_service.dart';
import '../services/user_state.dart';
import '../services/user_prefs_service.dart';
import '../services/personalization_service.dart';
import '../services/post_like_helper.dart';
import '../services/view_tracker.dart';
import '../onboarding/onboarding_anchors.dart';
import '../widgets/content_audience_sheet.dart';
import '../widgets/club_avatar.dart';
import '../widgets/club_follow_button.dart';
import '../widgets/event_cover_image.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/dynamic_contrast_text.dart';
import '../widgets/user_follow_button.dart';
import '../theme/app_semantic_colors.dart';
import '../models/share.dart';
import '../models/content_audience.dart';
import '../models/news_post.dart';
import '../models/event.dart';
import '../models/user.dart';
import '../models/club.dart';
import '../models/feed_v2.dart';
import '../models/notification.dart';
import 'user_profile_screen.dart';
import 'club_profile_screen.dart';
import 'create_post_screen.dart' show buildPostBanner;
import '../widgets/big_picture_post_composer_sheet.dart';
import '../widgets/club_home_design.dart';
import '../widgets/clubup_design.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/home_design.dart';
import '../widgets/moderation_reason_sheet.dart';
import '../services/comment_store.dart';
import '../widgets/user_avatar.dart';
import '../widgets/mutual_followers_badge.dart';
import '../services/rsvp_store.dart';
import '../services/poll_store.dart';
import '../widgets/rsvp_button.dart';
import '../widgets/expandable_post_caption.dart';
import '../widgets/poll_card.dart';
import '../widgets/post_share_sheet.dart';
import '../widgets/app_pressable.dart';
import '../widgets/app_motion.dart';
import '../widgets/instagram_refresh_control.dart';
import '../services/supabase_interaction_service.dart';
import '../services/supabase_post_service.dart';
import '../services/notification_inbox_service.dart';
import '../services/notification_navigation.dart';
import 'notifications_screen.dart';
import 'this_week_screen.dart';
import 'event_detail_screen.dart';

// ─── Feed Item (unified post + event wrapper) ─────────────────────────────────

class _FeedItem {
  final String id;
  final bool isEvent; // true = Event, false = NewsPost
  final dynamic data; // NewsPost | Event
  final double score;
  final DateTime postedAt;

  const _FeedItem({
    required this.id,
    required this.isEvent,
    required this.data,
    required this.score,
    required this.postedAt,
  });
}

// Inline recommendation marker types
class _EventSuggestion {
  final Event event;
  const _EventSuggestion(this.event);
}

class _ClubSuggestion {
  final dynamic club;
  const _ClubSuggestion(this.club);
}

Club? _clubById(String id) => clubForId(id);

const double _portraitFeedAspectRatio = 4 / 5;
const double _landscapeFeedAspectRatio = 1.91;

double _homeFeedPhotoHeight(double viewportWidth, {double aspectRatio = 1}) {
  final safeRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1;
  return viewportWidth /
      safeRatio.clamp(_portraitFeedAspectRatio, _landscapeFeedAspectRatio);
}

/// Memoized output of the feed pipeline. The pipeline (filter + sort of all
/// posts, three suggestion rankers, the events-rail window) used to rerun on
/// every rebuild — theme/locale ticks, contentStore notifies, any card
/// callback. Now it reruns only when [_FeedScreenState._feedSignature]
/// changes; everything else costs one hash comparison.
class _FeedCache {
  int? sig;
  List<dynamic>? mixed;
  List<Event>? railShown;
}

/// Controls actions on the already-mounted Home feed from the main nav.
class FeedController extends ChangeNotifier {
  void scrollToTop() => notifyListeners();
}

/// A restrained iOS-style edge bounce for both ends of the Home feed.
///
/// It keeps the same ballistic behavior as [BouncingScrollPhysics], including
/// recovery after slow drags and fast flings, but applies more resistance once
/// the content is out of range. The lightly elastic spring always settles back
/// on the real content extent, so overscroll can never become a resting state.
class _FeedBouncePhysics extends BouncingScrollPhysics {
  const _FeedBouncePhysics({super.parent});

  @override
  _FeedBouncePhysics applyTo(ScrollPhysics? ancestor) {
    return _FeedBouncePhysics(parent: buildParent(ancestor));
  }

  @override
  double frictionFactor(double overscrollFraction) {
    return super.frictionFactor(overscrollFraction) * 0.62;
  }

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 0.45,
    stiffness: 110,
    ratio: 0.92,
  );
}

// ─── Feed Screen ──────────────────────────────────────────────────────────────

class FeedScreen extends StatefulWidget {
  final FeedController? controller;

  const FeedScreen({super.key, this.controller});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  // 0 = Following (followed clubs only), 1 = All
  int _feedTab = 1;

  // At rest nothing but the scaffold background sits under the pinned glass
  // bar, so its sigma-14 backdrop blur is visually a no-op at full GPU price.
  // Only render the blur once content has actually scrolled under the bar —
  // pixel-identical in both states (the translucent fill is the same).
  bool _scrolledUnder = false;
  bool _studentHeaderControlsVisible = true;
  int _refreshCycle = 0;
  Future<void>? _refreshTask;
  final ScrollController _scrollController = ScrollController();
  late final FeedV2Controller _pagingController;
  final Map<String, NewsPost> _feedV2PostsById = {};
  final Map<String, Event> _feedV2EventsById = {};
  final Map<String, User> _feedV2PeopleById = {};
  final Map<String, Club> _feedV2ClubsById = {};
  int _appliedFeedV2Revision = -1;
  int _appliedFirstPageRevision = -1;
  final Set<String> _appliedFeedV2ItemIds = {};

  _FeedCache? _feedCache;

  /// Structural hash of every input the feed pipeline reads. Bulk hydration
  /// clears+refills the global lists with new instances, so first/last
  /// identity flips even at equal length; a like/unlike changes likes.length;
  /// follows change the unordered set hashes; people-directory loads reassign
  /// the cached lists. Theme/locale are deliberately NOT inputs. The 1-minute
  /// bucket bounds staleness of DateTime.now()-derived output (rail window,
  /// trending recency) — the same class of staleness it had when it only
  /// refreshed on incidental rebuilds.
  int _feedSignature() {
    return Object.hash(
      newsPosts.length,
      Object.hashAll(
        newsPosts.map(
          (post) => Object.hash(post.id, post.clubId, post.createdAt),
        ),
      ),
      events.length,
      events.isEmpty ? 0 : identityHashCode(events.first),
      clubs.length,
      clubs.isEmpty ? 0 : identityHashCode(clubs.first),
      likes.length,
      shares.length,
      _feedTab,
      Object.hashAllUnordered(userState.followedClubIds),
      Object.hashAllUnordered(userState.followedUserIds),
      Object.hashAllUnordered(moderationService.hiddenPostIds),
      Object.hashAllUnordered(moderationService.blockedUserIds),
      identityHashCode(peopleService.cachedPeople),
      identityHashCode(peopleService.cachedFollowerIds),
      peopleService.mutualFollowersRevision,
      Object.hashAllUnordered(personalizationService.interests),
      Object.hash(
        supabaseClubMemberCounts.length,
        supabasePostLikeCounts.length,
        _pagingController.items.length,
        _pagingController.items.isEmpty ? '' : _pagingController.items.last.id,
        DateTime.now().millisecondsSinceEpoch ~/ 60000,
      ),
    );
  }

  List<dynamic> _mixedFeed() {
    final sig = _feedSignature();
    final cache = _feedCache ??= _FeedCache();
    if (cache.sig != sig || cache.mixed == null) {
      cache.sig = sig;
      cache.mixed = _buildMixedFeed(_buildFeed());
      cache.railShown = _computeRailShown();
      // Seeding the RSVP store belongs with the (re)computation, not with
      // every rebuild: seedAll is idempotent and doesn't notify.
      final userId =
          authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
      rsvpStore.seedAll(cache.railShown!, userId);
    }
    return cache.mixed!;
  }

  /// What the Home list renders. The redesigned student Home (`home-feed-alt`
  /// in ClubUp-Desings) is posts only, so the suggestion rails the mixed feed
  /// injects are dropped there; club-admin sessions keep the full mix.
  List<dynamic> _homeFeedItems() {
    final mixed = _mixedFeed();
    // CLUB HOME's `feed-scroller-content` is posts only as well, so both
    // redesigned Homes drop the suggestion rails; the platform moderator's
    // un-redesigned Home keeps the full mix.
    if (!authService.isStudentSession && !_isClubSession) return mixed;
    return mixed.whereType<_FeedItem>().toList(growable: false);
  }

  List<Event> _computeRailShown() {
    final now = DateTime.now();
    final weekEnd = now.add(const Duration(days: 7));
    final eventSource = _pagingController.hasLoadedFirstPage
        ? _pagingController.upcomingEvents
              .map((event) => _feedV2EventsById[event.id])
              .whereType<Event>()
        : events;
    final weekEvents =
        eventSource
            .where(
              (e) =>
                  !moderationService.isClubBlocked(e.clubId) &&
                  canViewEvent(e) &&
                  e.dateTime.isAfter(now.subtract(const Duration(hours: 2))) &&
                  e.dateTime.isBefore(weekEnd),
            )
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return weekEvents.take(10).toList();
  }

  bool get _followedOnly => authService.isStudentSession && _feedTab == 0;

  void _selectFeedTab(int tab) {
    if (_feedTab == tab) return;
    _feedTab = tab;
    _feedCache = null;
    _pagingController.reset(followedOnly: _followedOnly);
    unawaited(_pagingController.loadFirstPage(followedOnly: _followedOnly));
  }

  Set<String> get _followedIds => userState.followedClubIds;

  bool _clubVisible(String clubId) =>
      !moderationService.isClubBlocked(clubId) &&
      (!_followedOnly || _followedIds.contains(clubId));

  List<_FeedItem> _buildFeed() {
    final Iterable<NewsPost> postSource;
    if (_pagingController.hasLoadedFirstPage) {
      final loaded = _pagingController.items
          .map((item) => _feedV2PostsById[item.id])
          .whereType<NewsPost>()
          .toList();
      final loadedIds = loaded.map((post) => post.id).toSet();
      final newestLoaded = loaded.isEmpty ? null : loaded.first;
      // Existing post creation stays optimistic. Only a newly-created row
      // newer than this cursor chain is overlaid; historical rows loaded by a
      // legacy screen cannot inflate the v2 page.
      if (newestLoaded != null) {
        loaded.addAll(
          newsPosts.where(
            (post) =>
                !loadedIds.contains(post.id) &&
                (post.createdAt.isAfter(newestLoaded.createdAt) ||
                    (post.createdAt.isAtSameMomentAs(newestLoaded.createdAt) &&
                        post.id.compareTo(newestLoaded.id) > 0)),
          ),
        );
      }
      postSource = loaded;
    } else {
      postSource = newsPosts;
    }
    final items = postSource
        .where((post) => _clubById(post.clubId) != null)
        .where((post) => _clubVisible(post.clubId))
        .where((post) => !moderationService.isPostHidden(post))
        .where(canViewPost)
        .map(
          (post) => _FeedItem(
            id: post.id,
            isEvent: false,
            data: post,
            score: postScore(post.id),
            postedAt: post.createdAt,
          ),
        )
        .toList();
    items.sort((a, b) {
      final byTime = b.postedAt.compareTo(a.postedAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return items;
  }

  // Profile users to suggest in the feed. Prefer people who follow me but I do
  // not follow back, then other unfollowed profiles. If no eligible profiles
  // remain, the suggestion rail is omitted.
  List<User> _suggestedUsers() {
    if (!authService.isStudentSession) return const [];
    final myId =
        authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
    final myFollowing = userState.followedUserIds;
    final myFollowers = peopleService.cachedFollowerIds;
    final profileSource = _pagingController.hasLoadedFirstPage
        ? _pagingController.suggestedPeople
              .map((person) => _feedV2PeopleById[person.id])
              .whereType<User>()
        : peopleService.cachedPeople;
    final profiles = profileSource
        .where(
          (user) =>
              user.id != myId && !moderationService.isUserBlocked(user.id),
        )
        .toList();
    final suggested = <String, User>{};

    void addAll(Iterable<User> candidates) {
      for (final user in candidates) {
        suggested.putIfAbsent(user.id, () => user);
      }
    }

    addAll(
      profiles.where(
        (user) =>
            myFollowers.contains(user.id) && !myFollowing.contains(user.id),
      ),
    );

    final randomized = peopleService
        .randomProfiles(excludeId: myId)
        .where((user) => !myFollowing.contains(user.id))
        .toList();
    addAll(randomized);

    // Follow-backs stay first. Within each group, real mutual followers are
    // the strongest social proof; the existing daily shuffle breaks ties so
    // the rail does not become permanently static.
    final fallbackRank = {
      for (var i = 0; i < randomized.length; i++) randomized[i].id: i,
    };
    final result = suggested.values.toList()
      ..sort((a, b) {
        final aFollowsMe = myFollowers.contains(a.id);
        final bFollowsMe = myFollowers.contains(b.id);
        if (aFollowsMe != bFollowsMe) return aFollowsMe ? -1 : 1;

        final byMutuals = peopleService
            .mutualFollowerIdsFor(b.id)
            .length
            .compareTo(peopleService.mutualFollowerIdsFor(a.id).length);
        if (byMutuals != 0) return byMutuals;

        return (fallbackRank[a.id] ?? randomized.length).compareTo(
          fallbackRank[b.id] ?? randomized.length,
        );
      });
    return result;
  }

  // Clubs the user doesn't follow yet, ranked by how well they match the
  // user's interests, then by popularity — "which club should I follow next".
  List<dynamic> _suggestedClubs() {
    if (!authService.isStudentSession) return const [];
    final clubSource = _pagingController.hasLoadedFirstPage
        ? _pagingController.suggestedClubs
              .map((club) => _feedV2ClubsById[club.id])
              .whereType<Club>()
        : clubs;
    return clubSource
        .where((c) => !userState.followedClubIds.contains(c.id))
        .toList()
      ..sort((a, b) {
        final byInterest = personalizationService
            .interestMatchCount(b.id)
            .compareTo(personalizationService.interestMatchCount(a.id));
        if (byInterest != 0) return byInterest;
        return clubMemberCount(b.id).compareTo(clubMemberCount(a.id));
      });
  }

  // Most-viewed upcoming event from the last 14 days.
  Event? _trendingEvent() {
    if (!authService.isStudentSession) return null;
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 14));
    final eventSource = _pagingController.hasLoadedFirstPage
        ? _pagingController.upcomingEvents
              .map((event) => _feedV2EventsById[event.id])
              .whereType<Event>()
        : events;
    final eligible = eventSource
        .where(
          (e) =>
              canViewEvent(e) &&
              e.dateTime.isAfter(cutoff) &&
              e.endTime.isAfter(now),
        )
        .toList();
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) {
      final scoreA = viewTracker.viewCount(a.id) + eventScore(a.id);
      final scoreB = viewTracker.viewCount(b.id) + eventScore(b.id);
      return scoreB.compareTo(scoreA);
    });
    return eligible.first;
  }

  // Builds the mixed feed. Each recommendation type is inserted at most once;
  // repeating tall rails buried club posts and caused large scroll corrections
  // when several copies disappeared after one follow action.
  // Tapping any suggestion opens that person, event, or club.
  List<dynamic> _buildMixedFeed(List<_FeedItem> posts) {
    final result = <dynamic>[];
    final peopleSuggestions = _suggestedUsers();
    final clubSuggestions = _suggestedClubs();
    final trendingEv = _trendingEvent();
    var addedPeople = false;
    var addedEvent = false;
    var addedClub = false;

    for (int i = 0; i < posts.length; i++) {
      result.add(posts[i]);
      final n = i + 1;
      if (!addedPeople && n >= 10 && peopleSuggestions.isNotEmpty) {
        result.add(peopleSuggestions);
        addedPeople = true;
      }
      if (!addedEvent && n >= 15 && trendingEv != null) {
        result.add(_EventSuggestion(trendingEv));
        addedEvent = true;
      }
      if (!addedClub && n >= 20 && clubSuggestions.isNotEmpty) {
        result.add(_ClubSuggestion(clubSuggestions.first));
        addedClub = true;
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _pagingController = FeedV2Controller(source: supabaseFeedV2Service)
      ..addListener(_onFeedV2Changed);
    _scrollController.addListener(_onFeedScroll);
    widget.controller?.addListener(_scrollToTop);
    localeService.addListener(_onLocaleChanged);
    themeService.addListener(_onLocaleChanged);
    accountSwitcherService.addListener(_onAccountChanged);
    contentStore.addListener(_onContentChanged);
    moderationService.addListener(_onContentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(notificationInboxService.startForCurrentUser());
    });
    unawaited(_pagingController.loadFirstPage(followedOnly: _followedOnly));
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_scrollToTop);
    _scrollController.removeListener(_onFeedScroll);
    _pagingController.removeListener(_onFeedV2Changed);
    _pagingController.dispose();
    _scrollController.dispose();
    localeService.removeListener(_onLocaleChanged);
    themeService.removeListener(_onLocaleChanged);
    accountSwitcherService.removeListener(_onAccountChanged);
    contentStore.removeListener(_onContentChanged);
    moderationService.removeListener(_onContentChanged);
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients || _scrollController.offset <= 0) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _onAccountChanged() {
    if (!mounted) return;
    _feedCache = null;
    _feedV2PostsById.clear();
    _feedV2EventsById.clear();
    _feedV2PeopleById.clear();
    _feedV2ClubsById.clear();
    _appliedFeedV2ItemIds.clear();
    supabaseFeedV2Service.invalidateFirstPages();
    _pagingController.reset(followedOnly: _followedOnly);
    unawaited(
      _pagingController.loadFirstPage(followedOnly: _followedOnly, force: true),
    );
  }

  void _onContentChanged() {
    if (!mounted) return;
    // The mixed feed and events rail retain Event instances. An edit replaces
    // the Event in the global list, so a rebuild alone is not enough: discard
    // the cached instances before rebuilding the Home visuals.
    _feedCache = null;
    if (_pagingController.hasLoadedFirstPage) {
      final globalIds = newsPosts.map((post) => post.id).toSet();
      final removedIds = _pagingController.items
          .map((item) => item.id)
          .where((id) => !globalIds.contains(id))
          .toList();
      if (removedIds.isNotEmpty) {
        _feedV2PostsById.removeWhere((id, _) => removedIds.contains(id));
        _pagingController.removeItems(removedIds);
        return;
      }
    }
    setState(() {});
  }

  void _onFeedScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 900) {
      unawaited(_pagingController.loadNextPage());
    }
  }

  void _onFeedV2Changed() {
    if (!mounted) return;
    if (_pagingController.hasLoadedFirstPage &&
        _appliedFeedV2Revision != _pagingController.dataRevision) {
      final replacedFirstPage =
          _appliedFirstPageRevision != _pagingController.firstPageRevision;
      _applyFeedV2Snapshot(replace: replacedFirstPage);
      _appliedFirstPageRevision = _pagingController.firstPageRevision;
      _appliedFeedV2Revision = _pagingController.dataRevision;
    }
    _feedCache = null;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onFeedScroll();
    });
  }

  void _applyFeedV2Snapshot({required bool replace}) {
    final viewerId = authService.currentUser?.id ?? '';
    final likeStates = <String, bool>{};
    final commentCounts = <String, int>{};
    final viewCounts = <String, int>{};
    final likerPreviews = <String, User?>{};
    final pollCounts = <String, List<int>>{};
    final pollVotes = <String, int?>{};

    if (replace) _appliedFeedV2ItemIds.clear();
    final itemsToApply = replace
        ? _pagingController.items
        : _pagingController.items
              .where((item) => !_appliedFeedV2ItemIds.contains(item.id))
              .toList(growable: false);

    for (final item in itemsToApply) {
      final club = _upsertFeedClub(item.club);
      final author = item.author == null
          ? null
          : _upsertFeedPerson(item.author!);
      final post = NewsPost(
        id: item.id,
        clubId: club.id,
        authorId: author?.id ?? '',
        content: item.content,
        createdAt: item.createdAt,
        imagePath: item.mediaUrl,
        poll: item.poll == null
            ? null
            : PollData(
                pollId: item.poll!.id,
                question: item.poll!.question,
                options: item.poll!.options,
              ),
        isAnnouncement: item.isAnnouncement,
      );
      _feedV2PostsById[item.id] = post;
      _upsertGlobalPost(post);

      likeStates[item.id] = item.engagement.viewerHasLiked;
      supabasePostLikeCounts[item.id] = item.engagement.likeCount;
      commentCounts[item.id] = item.engagement.commentCount;
      viewCounts[item.id] = item.engagement.viewCount;
      likerPreviews[item.id] = item.engagement.firstLiker == null
          ? null
          : _upsertFeedPerson(item.engagement.firstLiker!);
      final poll = item.poll;
      if (poll != null) {
        pollCounts[item.id] = poll.optionCounts;
        pollVotes[item.id] = poll.viewerOptionIndex;
      }
      _appliedFeedV2ItemIds.add(item.id);
    }

    if (!replace) {
      userState.seedFeedLikeStates(likeStates);
      commentStore.seedFeedCounts(commentCounts);
      viewTracker.seedFeedViewCounts(viewCounts);
      supabaseInteractionService.seedFeedLikerPreviews(likerPreviews);
      pollStore.seedFeedSummaries(
        optionCountsByPostId: pollCounts,
        viewerVotesByPostId: pollVotes,
        userId: viewerId,
      );
      return;
    }

    final suggestedUsers = <User>[];
    final followerIds = <String>[];
    for (final person in _pagingController.suggestedPeople) {
      final user = _upsertFeedPerson(person);
      suggestedUsers.add(user);
      if (person.followsViewer) followerIds.add(person.id);
    }
    peopleService.seedFeedSuggestions(suggestedUsers, followerIds: followerIds);

    for (final club in _pagingController.suggestedClubs) {
      _upsertFeedClub(club);
      supabaseClubMemberCounts[club.id] = club.memberCount;
    }

    for (final item in _pagingController.upcomingEvents) {
      final club = _upsertFeedClub(item.club);
      final attendeeIds = item.viewerIsAttending && viewerId.isNotEmpty
          ? <String>[viewerId]
          : <String>[];
      final event = Event(
        id: item.id,
        clubId: club.id,
        title: item.title,
        description: item.description,
        dateTime: item.startsAt,
        endTime: item.endsAt,
        location: item.location,
        attendeeUserIds: attendeeIds,
        imagePath: item.mediaUrl,
        createdByUserId: item.createdByUserId,
        tags: item.tags,
        registrationUrl: item.registrationUrl,
        schedule: _feedEventSchedule(item.schedule),
        speakers: _feedEventSpeakers(item.speakers),
      );
      _feedV2EventsById[item.id] = event;
      _upsertGlobalEvent(event);
      supabaseEventRsvpCounts[item.id] = item.rsvpCount;
      rsvpStore.seed(item.id, item.viewerIsAttending);
    }

    userState.seedFeedLikeStates(likeStates);
    commentStore.seedFeedCounts(commentCounts);
    viewTracker.seedFeedViewCounts(viewCounts);
    supabaseInteractionService.seedFeedLikerPreviews(likerPreviews);
    pollStore.seedFeedSummaries(
      optionCountsByPostId: pollCounts,
      viewerVotesByPostId: pollVotes,
      userId: viewerId,
    );
  }

  Club _upsertFeedClub(FeedClubV2 item) {
    final existing = clubForId(item.id);
    final club =
        existing ??
        Club(
          id: item.id,
          name: item.name,
          shortName: item.shortName,
          description: item.description,
          logoUrl: item.logoUrl,
          categoryId: item.categoryId,
          adminUserIds: const [],
          createdAt: item.createdAt,
        );
    if (existing == null) clubs.add(club);
    _feedV2ClubsById[item.id] = club;
    if (item.logoUrl != null) {
      userState.remoteClubPhotoUrls[item.id] = item.logoUrl!;
    }
    return club;
  }

  User _upsertFeedPerson(FeedPersonV2 item) {
    User? existing;
    for (final candidate in users) {
      if (candidate.id == item.id) {
        existing = candidate;
        break;
      }
    }
    final user =
        existing ??
        User(
          id: item.id,
          name: item.name,
          email: '',
          password: '',
          role: item.role,
          subscribedClubIds: const [],
        );
    if (existing == null) users.add(user);
    _feedV2PeopleById[item.id] = user;
    final avatarUrl = item.avatarUrl;
    if (avatarUrl != null) userState.remotePhotoUrls[item.id] = avatarUrl;
    final bio = item.bio;
    if (bio != null) userState.bios[item.id] = bio;
    return user;
  }

  List<EventSlot>? _feedEventSchedule(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;
    final result = <EventSlot>[];
    for (final row in rows) {
      try {
        result.add(EventSlot.fromMap(row));
      } catch (_) {
        // Ignore a malformed optional schedule row; the event card remains.
      }
    }
    return result.isEmpty ? null : result;
  }

  List<EventSpeaker> _feedEventSpeakers(List<Map<String, dynamic>> rows) {
    final result = <EventSpeaker>[];
    for (final row in rows) {
      try {
        result.add(EventSpeaker.fromMap(row));
      } catch (_) {
        // Ignore malformed optional speaker metadata.
      }
    }
    return result;
  }

  void _upsertGlobalPost(NewsPost post) {
    final index = newsPosts.indexWhere((item) => item.id == post.id);
    if (index < 0) {
      newsPosts.add(post);
    } else {
      newsPosts[index] = post;
    }
  }

  void _upsertGlobalEvent(Event event) {
    final index = events.indexWhere((item) => item.id == event.id);
    if (index < 0) {
      events.add(event);
    } else {
      events[index] = event;
    }
  }

  Future<void> _onRefresh() async {
    final activeTask = _refreshTask;
    if (activeTask != null) {
      await activeTask;
      return;
    }

    late final Future<void> refreshTask;
    refreshTask = _performRefresh();
    _refreshTask = refreshTask;
    try {
      await refreshTask;
    } finally {
      if (identical(_refreshTask, refreshTask)) {
        _refreshTask = null;
      }
    }
  }

  Future<void> _performRefresh() async {
    // Instagram keeps the activity ring visible long enough to register even
    // when a cached/offline refresh resolves immediately.
    final stopwatch = Stopwatch()..start();
    try {
      try {
        supabaseFeedV2Service.invalidateFirstPages();
        await _pagingController.refresh();
      } catch (_) {
        // Keep currently loaded content if the network request fails.
      }
    } finally {
      stopwatch.stop();
      const minimumSpinTime = Duration(milliseconds: 850);
      final remaining = minimumSpinTime - stopwatch.elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);

      // Let CupertinoSliverRefreshControl animate its temporary pull space
      // closed before rotating its key for the next gesture.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 360), () {
          if (!mounted || _refreshTask != null) return;
          setState(() => _refreshCycle++);
        }),
      );
    }
  }

  /// The CLUB HOME point of view: the club-admin login and a student who has
  /// switched to their club account. Same condition the bottom nav uses to
  /// swap Search for the create button, so the two chromes always agree.
  /// Platform moderators are deliberately excluded — their Home has no frame
  /// in the handoff yet.
  bool get _isClubSession {
    if (accountSwitcherService.isClubAccountActive) return true;
    final admin = authService.currentAdmin;
    return admin != null && !isClubUpAdmin(admin);
  }

  /// The club a club session posts as.
  Club? get _sessionClub {
    final linked = accountSwitcherService.activeClub;
    if (linked != null) return linked;
    final admin = authService.currentAdmin;
    return admin == null ? null : managedClubForAdmin(admin.id);
  }

  @override
  Widget build(BuildContext context) {
    final designClubHome = _isClubSession;
    final designHome = authService.isStudentSession && !designClubHome;
    final mixed = _homeFeedItems();
    final showFeedSkeleton =
        _pagingController.isInitialLoading && mixed.isEmpty;
    return Scaffold(
      backgroundColor: designClubHome
          ? ClubHomeColors.page
          : designHome
          ? ClubUpColors.background
          : AppColors.background,
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // Vertical feed scroll only (depth 0) — not the horizontal events
          // rail. The glass state changes only on threshold crossings; while
          // pulling, the refresh sliver owns the temporary top space and its
          // indicator. Post-_FeedCache, either rebuild is just a hash compare.
          if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
          // Any downward travel at all counts as scrolled-under: the flat
          // header is only correct while the feed is pinned at pixel 0. The
          // 180ms crossfade below absorbs the jitter this would otherwise
          // cause on flicks right at the boundary.
          final under = n.metrics.pixels > 0.0;
          var showStudentHeaderControls = _studentHeaderControlsVisible;
          if (designHome || designClubHome) {
            if (!under) showStudentHeaderControls = true;
            if (n is UserScrollNotification) {
              if (n.direction == ScrollDirection.reverse) {
                showStudentHeaderControls = false;
              } else if (n.direction == ScrollDirection.forward) {
                showStudentHeaderControls = true;
              }
            }
          }
          if (under != _scrolledUnder ||
              showStudentHeaderControls != _studentHeaderControlsVisible) {
            setState(() {
              _scrolledUnder = under;
              _studentHeaderControlsVisible = showStudentHeaderControls;
            });
          }
          return false;
        },
        child: CustomScrollView(
          scrollDirection: Axis.vertical,
          controller: _scrollController,
          physics: const _FeedBouncePhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            InstagramRefreshControl(
              key: ValueKey('home-refresh-control-$_refreshCycle'),
              onRefresh: _onRefresh,
              refreshIndicatorExtent: 60,
              indicatorKey: const ValueKey('home-refresh-indicator'),
            ),
            if (designClubHome) ...[
              _buildDesignTopBar(),
              _buildClubDesignComposer(),
              _buildClubComposerDivider(),
            ] else if (designHome) ...[
              _buildDesignTopBar(),
            ] else ...[
              _buildTopBar(),
              _buildGreeting(),
              _buildEventsRail(),
              _buildFeedTabs(),
              _buildComposer(),
            ],
            if (showFeedSkeleton) ...[
              ..._buildFeedSkeletonSlivers(),
            ] else if (_pagingController.initialError != null && mixed.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 36,
                          color: AppColors.secondaryText,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context)!.couldNotLoadPeople,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.secondaryText),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          key: const ValueKey('feed-v2-initial-retry'),
                          onPressed: () => unawaited(_pagingController.retry()),
                          child: Text(AppLocalizations.of(context)!.retry),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (mixed.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const GentleFloat(child: _EmptyFeedArt()),
                        const SizedBox(height: 18),
                        Text(
                          AppLocalizations.of(context)!.nothingHere,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context)!.followClubs,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.secondaryText,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _selectFeedTab(1),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            elevation: 0,
                          ),
                          icon: Icon(Icons.explore_rounded, size: 18),
                          label: Text(
                            AppLocalizations.of(context)!.exploreClubs,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              // Neither design has a section label above the cards.
              if (!designHome && !designClubHome)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                    child: Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.latest,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (designClubHome)
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final item = mixed[i] as _FeedItem;
                    final post = item.data as NewsPost;
                    return KeyedSubtree(
                      key: ValueKey('home-feed-item-${item.id}'),
                      child: StaggeredEntrance(
                        index: i,
                        child: HomeFeedPostCard(
                          key: ValueKey('club-home-card-${item.id}'),
                          post: post,
                          onChanged: () => setState(() {}),
                          clubContext: true,
                        ),
                      ),
                    );
                  }, childCount: mixed.length),
                )
              else if (designHome)
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final item = mixed[i] as _FeedItem;
                    final post = item.data as NewsPost;
                    return KeyedSubtree(
                      key: ValueKey('home-feed-item-${item.id}'),
                      child: StaggeredEntrance(
                        index: i,
                        child: HomeFeedPostCard(
                          key: ValueKey('home-design-card-${item.id}'),
                          post: post,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    );
                  }, childCount: mixed.length),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final item = mixed[i];
                    if (item is List<User>) {
                      return _PeopleSuggestionCard(
                        key: const ValueKey('home-people-suggestions'),
                        suggestions: item,
                        onFollowed: () => setState(() {}),
                      );
                    }
                    if (item is _EventSuggestion) {
                      return _TrendingEventCard(
                        key: ValueKey('home-event-suggestion-${item.event.id}'),
                        event: item.event,
                        onUpdate: () => setState(() {}),
                      );
                    }
                    if (item is _ClubSuggestion) {
                      return _ClubSuggestionCard(
                        key: ValueKey('home-club-suggestion-${item.club.id}'),
                        club: item.club,
                        onUpdate: () => setState(() {}),
                      );
                    }
                    final feedItem = item as _FeedItem;
                    return KeyedSubtree(
                      key: ValueKey('home-feed-item-${feedItem.id}'),
                      child: _buildFeedCard(feedItem, i),
                    );
                  }, childCount: mixed.length),
                ),
              if (_pagingController.isNextPageLoading)
                const SliverToBoxAdapter(
                  child: SizedBox(
                    key: ValueKey('feed-v2-next-loading'),
                    height: 64,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_pagingController.pageError != null)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 72,
                    child: Center(
                      child: TextButton.icon(
                        key: const ValueKey('feed-v2-page-retry'),
                        onPressed: () => unawaited(_pagingController.retry()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(AppLocalizations.of(context)!.retry),
                      ),
                    ),
                  ),
                )
              else if (!_pagingController.hasMore)
                SliverToBoxAdapter(
                  child: Semantics(
                    key: const ValueKey('home-feed-end'),
                    container: true,
                    child: SizedBox(
                      height: 56,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.endOfFeed,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondaryText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '🙂',
                              style: TextStyle(fontSize: 18, height: 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // `feed-scroller-content` ends on 100pt of clearance for the
              // floating bottom nav.
              if (designHome || designClubHome)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom + 100,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFeedSkeletonSlivers() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: SkeletonBox(
            width: 70,
            height: 18,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) =>
              StaggeredEntrance(index: i, child: const _FeedPostSkeleton()),
          childCount: 4,
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 112),
      ),
    ];
  }

  String get _greetingName {
    final activeClub = accountSwitcherService.activeClub;
    if (activeClub != null) return '@${clubHandle(activeClub)}';
    final student = authService.currentUser;
    if (authService.isStudentSession && student != null) {
      return _firstName(student.name);
    }

    final admin = authService.currentAdmin;
    if (admin != null) {
      final club = managedClubForAdmin(admin.id);
      return club != null ? '@${clubHandle(club)}' : _firstName(admin.name);
    }

    return '';
  }

  String _firstName(String fullName) {
    final parts = fullName.trim().split(' ');
    return parts.isNotEmpty && parts.first.isNotEmpty ? parts.first : fullName;
  }

  /// Unread notifications behind the bell — local rows plus whatever the
  /// inbox service has fetched. Shared by both Home headers.
  int _unreadNotificationCount() {
    final myId =
        authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
    final unreadIds = <String>{};
    for (final notification
        in [...notifications, ...userState.dynamicNotifications].where(
          (n) =>
              canViewNotification(n, currentUserId: myId) &&
              n.targetType != 'story' &&
              !userState.isNotificationRead(n),
        )) {
      unreadIds.add(notification.id);
    }
    for (final row in notificationInboxService.rows) {
      final notification = AppNotification(
        id: row['id']?.toString() ?? '',
        userId: row['user_id']?.toString() ?? '',
        fromId: row['actor_user_id']?.toString(),
        message: row['body']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        read: row['read_at'] != null,
        notificationType: row['type']?.toString(),
        targetType: row['target_type']?.toString(),
        targetId: row['target_id']?.toString(),
      );
      if (row['read_at'] == null &&
          canViewNotification(notification, currentUserId: myId)) {
        unreadIds.add(notification.id);
      }
    }
    return unreadIds.length;
  }

  // ── ClubUp top bar — redesigned student Home ──────────────────────────────
  /// Shared student/club header with greeting, feed-scope dropdown and bell.
  SliverAppBar _buildDesignTopBar() {
    return SliverAppBar(
      key: const ValueKey('home-active-feed-header'),
      pinned: true,
      floating: false,
      automaticallyImplyLeading: false,
      forceMaterialTransparency: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      toolbarHeight: 81,
      titleSpacing: 0,
      leading: const SizedBox.shrink(),
      leadingWidth: 0,
      title: ListenableBuilder(
        listenable: Listenable.merge([userState, notificationInboxService]),
        builder: (_, _) => HomeFeedHeader(
          greetingName: _greetingName,
          feedTab: _feedTab,
          onSelectFeedTab: (tab) => setState(() => _selectFeedTab(tab)),
          unreadCount: _unreadNotificationCount(),
          atTop: !_scrolledUnder,
          controlsVisible: _studentHeaderControlsVisible,
          showFeedScope: !_isClubSession,
          scopeAnchorKey: onboardingAnchors.keyFor(
            OnboardingAnchors.homeFeedToggle,
          ),
          onBellTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => NotificationsScreen()),
          ),
        ),
      ),
    );
  }

  // ── CLUB HOME — `home-feed-alt` 272:31 / 272:200 ─────────────────────────
  /// `admin-compose` 298:5. A club session with no club behind it (a linked
  /// account whose club row has gone) has nothing to post as, so the card is
  /// simply absent rather than inert.
  SliverToBoxAdapter _buildClubDesignComposer() {
    final club = _sessionClub;
    if (club == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        key: onboardingAnchors.keyFor(OnboardingAnchors.clubQuickComposer),
        padding: const EdgeInsets.fromLTRB(
          kClubHomeGutter,
          0,
          kClubHomeGutter,
          10,
        ),
        child: ClubHomeComposerCard(
          key: ValueKey('club-home-composer-${club.id}'),
          club: club,
          onPosted: () => setState(() {}),
        ),
      ),
    );
  }

  // ── ClubUp top bar ────────────────────────────────────────────────────────
  /// Strong boundary between the club authoring controls and its public feed.
  SliverToBoxAdapter _buildClubComposerDivider() {
    return SliverToBoxAdapter(
      child: Container(
        key: const ValueKey('club-home-composer-divider'),
        width: double.infinity,
        height: 3,
        color: themeService.isDark ? Colors.white : ClubUpColors.text,
      ),
    );
  }

  SliverAppBar _buildTopBar() {
    // At rest, the app bar blends into the screen background. Once content
    // scrolls underneath, that full-width fill fades away completely so only
    // the ClubUp wordmark and the bell's own floating button remain visible.
    final flatColor = AppColors.background;
    return SliverAppBar(
      key: const ValueKey('home-active-feed-header'),
      pinned: true,
      floating: false,
      forceMaterialTransparency: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      toolbarHeight: 56,
      leading: const SizedBox.shrink(),
      leadingWidth: 0,
      titleSpacing: 0,
      // This remains part of the CustomScrollView, so a drag that begins on
      // the logo/background controls the same feed. The fill becomes fully
      // transparent while pinned, leaving no panel between the two controls.
      flexibleSpace: ClipRect(
        key: const ValueKey('home-feed-header-background'),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _scrolledUnder ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, t, _) {
            return IgnorePointer(
              child: Container(color: flatColor.withValues(alpha: 1 - t)),
            );
          },
        ),
      ),
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Stack(
          key: const ValueKey('home-top-bar-row'),
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                // ClubUp logotype — "Club" in maroon, "Up" in foreground,
                // gold dot.
                RichText(
                  key: const ValueKey('home-clubup-logo'),
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Club',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryRed,
                          letterSpacing: -0.8,
                        ),
                      ),
                      TextSpan(
                        text: 'Up',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 3, bottom: 12),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.accentGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const Spacer(),
                // Chats live in the bottom navigation. The bell is
                // intentionally the only shortcut in the Home top bar.
                ListenableBuilder(
                  listenable: Listenable.merge([
                    userState,
                    notificationInboxService,
                  ]),
                  builder: (_, x) {
                    return _TopBarIconButton(
                      key: const ValueKey('home-notifications-bell'),
                      icon: Icons.notifications_none_rounded,
                      semanticLabel: AppLocalizations.of(
                        context,
                      )!.notifications,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationsScreen(),
                        ),
                      ),
                      badgeCount: _unreadNotificationCount(),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Greeting ─────────────────────────────────────────────────────────────
  SliverToBoxAdapter _buildGreeting() {
    final h = DateTime.now().hour;
    final greet = h < 5
        ? AppLocalizations.of(context)!.stillUp
        : h < 12
        ? AppLocalizations.of(context)!.goodMorning
        : h < 17
        ? AppLocalizations.of(context)!.goodAfternoon
        : AppLocalizations.of(context)!.goodEvening;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: -1.0,
                  height: 1.15,
                ),
                children: [
                  TextSpan(text: '$greet, '),
                  TextSpan(
                    text: _greetingName,
                    style: TextStyle(color: AppColors.primaryRed),
                  ),
                  const TextSpan(text: ' 👋'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── This Week events rail ─────────────────────────────────────────────────
  SliverToBoxAdapter _buildEventsRail() {
    // Computed (and the RSVP store seeded) in _mixedFeed, once per data
    // change; build() runs _mixedFeed first so the cache is always warm here.
    final shown = _feedCache?.railShown ?? const <Event>[];

    if (shown.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.thisWeek,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.secondaryText,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          AppLocalizations.of(context)!.eventsOnCampus,
                          style: TextStyle(
                            fontSize: 19,
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ThisWeekScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.seeAll,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.primaryRed,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: AppColors.primaryRed,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 178,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: shown.length,
                separatorBuilder: (_, i) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) =>
                    _EventRailCard(key: ValueKey(shown[i].id), event: shown[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Feed section header + filter tabs ────────────────────────────────────
  SliverToBoxAdapter _buildFeedTabs() {
    if (!authService.isStudentSession) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text(
            AppLocalizations.of(context)!.clubFeed,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.secondaryText,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // tab 0 = Following, tab 1 = For You — pill segmented control with a sliding
    // maroon thumb (300ms ease-out) behind the active label.
    final labels = [S.following, S.forYou];
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Container(
          key: onboardingAnchors.keyFor(OnboardingAnchors.homeFeedToggle),
          height: 42,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.all(Radius.circular(100)),
            border: Border.all(color: AppColors.divider),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: _feedTab == 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed,
                      borderRadius: BorderRadius.all(Radius.circular(100)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryRed.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        key: ValueKey('home-feed-tab-$i'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectFeedTab(i),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _feedTab == i
                                  ? Colors.white
                                  : AppColors.secondaryText,
                              letterSpacing: -0.1,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Quick post composer (club admins only) ───────────────────────────────
  // Inline card for the managing admin to post a quick text update to their
  // club, mirroring the design's composer. Hidden for student sessions and
  // admins without a managed club, since only clubs author posts.
  Widget _buildComposer() {
    final linkedClub = accountSwitcherService.activeClub;
    if (linkedClub != null) {
      return SliverToBoxAdapter(
        child: Padding(
          key: onboardingAnchors.keyFor(OnboardingAnchors.clubQuickComposer),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: _QuickPostComposer(
            club: linkedClub,
            color: _colorForClub(linkedClub.id),
            onPosted: () => setState(() {}),
          ),
        ),
      );
    }
    final admin = authService.currentAdmin;
    if (admin == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final club = managedClubForAdmin(admin.id);
    if (club == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        key: onboardingAnchors.keyFor(OnboardingAnchors.clubQuickComposer),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: _QuickPostComposer(
          club: club,
          color: _colorForClub(club.id),
          onPosted: () => setState(() {}),
        ),
      ),
    );
  }

  Widget _buildFeedCard(_FeedItem item, int rank) {
    final Widget card;
    if (item.isEvent) {
      card = _EventCard(
        key: ValueKey(item.id),
        event: item.data as Event,
        score: item.score,
        rank: rank,
        onUpdate: () => setState(() {}),
      );
    } else {
      card = _PostCard(
        key: ValueKey(item.id),
        post: item.data as NewsPost,
        score: item.score,
        rank: rank,
      );
    }
    return StaggeredEntrance(
      key: ValueKey('feed-card-entrance-${item.id}'),
      index: rank,
      child: card,
    );
  }
}

/// Empty-feed illustration: a tilted cluster of three icon tiles with a gold
/// sparkle badge, matching the design's Following-tab empty state.
class _EmptyFeedArt extends StatelessWidget {
  const _EmptyFeedArt();

  Widget _tile(IconData icon, {double angle = 0, bool raised = false}) {
    return Transform.rotate(
      angle: angle,
      child: Transform.translate(
        offset: Offset(0, raised ? -8 : 0),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: raised ? AppColors.lightRed : AppColors.surfaceAlt,
            borderRadius: BorderRadius.all(Radius.circular(18)),
            border: Border.all(
              color: raised
                  ? AppColors.primaryRed.withValues(alpha: 0.25)
                  : AppColors.divider,
            ),
          ),
          child: Icon(
            icon,
            size: 24,
            color: raised ? AppColors.primaryRed : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile(Icons.calendar_today_rounded, angle: -0.14),
            const SizedBox(width: 2),
            _tile(Icons.people_alt_rounded, raised: true),
            const SizedBox(width: 2),
            _tile(Icons.image_rounded, angle: 0.14),
          ],
        ),
        Positioned(
          top: -16,
          right: -8,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accentGold.withValues(alpha: 0.45),
              ),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: AppColors.accentGold,
            ),
          ),
        ),
      ],
    );
  }
}

/// Squared glass icon button used in the ClubUp top bar (theme toggle, bell).
/// [badgeCount] > 0 shows a maroon unread-count pill on the top-right corner.
class _TopBarIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  final String semanticLabel;

  const _TopBarIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.badgeCount = 0,
  });

  @override
  State<_TopBarIconButton> createState() => _TopBarIconButtonState();
}

class _TopBarIconButtonState extends State<_TopBarIconButton>
    with SingleTickerProviderStateMixin {
  bool _isHandlingTap = false;

  late final AnimationController _bellController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _bellTurns = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -0.075), weight: 18),
    TweenSequenceItem(tween: Tween(begin: -0.075, end: 0.065), weight: 24),
    TweenSequenceItem(tween: Tween(begin: 0.065, end: -0.04), weight: 22),
    TweenSequenceItem(tween: Tween(begin: -0.04, end: 0.022), weight: 20),
    TweenSequenceItem(tween: Tween(begin: 0.022, end: 0), weight: 16),
  ]).animate(CurvedAnimation(parent: _bellController, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant _TopBarIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.badgeCount <= oldWidget.badgeCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
      _bellController.forward(from: 0);
    });
  }

  Future<void> _handleTap() async {
    if (_isHandlingTap) return;
    _isHandlingTap = true;
    HapticFeedback.selectionClick();

    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onTap();
      _isHandlingTap = false;
      return;
    }

    _bellController.forward(from: 0);
    // Let the first swing register before the destination starts sliding in.
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (mounted) {
      widget.onTap();
      _isHandlingTap = false;
    }
  }

  @override
  void dispose() {
    _bellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      value: widget.badgeCount > 0 ? '${widget.badgeCount}' : null,
      child: Tooltip(
        message: widget.semanticLabel,
        child: AppPressable(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.65),
              borderRadius: BorderRadius.all(Radius.circular(12)),
              border: Border.all(color: AppColors.divider),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: AnimatedBuilder(
                    animation: _bellTurns,
                    child: Icon(widget.icon, size: 18, color: AppColors.text),
                    builder: (context, child) => Transform.rotate(
                      key: const ValueKey('top-bar-icon-motion'),
                      angle: _bellTurns.value * math.pi * 2,
                      child: child,
                    ),
                  ),
                ),
                if (widget.badgeCount > 0)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('top-bar-badge-${widget.badgeCount}'),
                      tween: Tween(begin: 0.55, end: 1),
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 320),
                      curve: Curves.elasticOut,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed,
                          borderRadius: BorderRadius.all(Radius.circular(100)),
                          border: Border.all(color: AppColors.card, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          widget.badgeCount > 9 ? '9+' : '${widget.badgeCount}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
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

class _FeedPostSkeleton extends StatelessWidget {
  const _FeedPostSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(
            color: AppColors.divider.withValues(alpha: 0.7),
            width: 0.6,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonBox.circle(size: 44),
              const SizedBox(width: 11),
              SkeletonBox(
                width: 128,
                height: 14,
                borderRadius: BorderRadius.all(Radius.circular(7)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SkeletonBox(
            width: double.infinity,
            height: _homeFeedPhotoHeight(MediaQuery.sizeOf(context).width),
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          const SizedBox(height: 10),
          SkeletonBox(
            width: double.infinity,
            height: 12,
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          const SizedBox(height: 6),
          SkeletonBox(
            width: MediaQuery.sizeOf(context).width * 0.58,
            height: 12,
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Post Composer ──────────────────────────────────────────────────────

/// Tappable prompt shown at the top of the feed for the managing club admin.
/// Tapping it opens the "Option C — Big Picture Cards" bottom sheet composer
/// (see [showBigPicturePostComposerSheet]), which handles both text and
/// photo posts and publishes through the same path as CreatePostScreen.
class _QuickPostComposer extends StatelessWidget {
  final dynamic club; // Club
  final Color color;
  final VoidCallback onPosted;

  const _QuickPostComposer({
    required this.club,
    required this.color,
    required this.onPosted,
  });

  void _openComposerSheet(BuildContext context) {
    showBigPicturePostComposerSheet(
      context: context,
      club: club,
      color: color,
      onPosted: onPosted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = AppColors.background;
    final textColor = AppColors.text;
    final secondaryTextColor = AppColors.secondaryText;

    return Material(
      color: surfaceColor,
      child: InkWell(
        onTap: () => _openComposerSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClubAvatar(
                key: ValueKey('quick-post-club-avatar-${club.id}'),
                clubId: club.id as String,
                clubName: club.name as String,
                color: textColor,
                size: 42,
                fontSize: 18,
                shape: 'circle',
                borderRadius: 13,
                imageUrl: club.logoUrl as String?,
                profilePhotoFallbackId: authService.currentAdmin?.id,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Read-only club label
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        club.name as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: secondaryTextColor,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)!.whatsHappeningAtClub,
                      style: TextStyle(
                        fontSize: 15,
                        color: secondaryTextColor,
                        height: 1.55,
                      ),
                    ),
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

// ─── People You Might Know ────────────────────────────────────────────────────

class _PeopleSuggestionCard extends StatefulWidget {
  final List<User> suggestions;
  final VoidCallback onFollowed;
  const _PeopleSuggestionCard({
    super.key,
    required this.suggestions,
    required this.onFollowed,
  });

  @override
  State<_PeopleSuggestionCard> createState() => _PeopleSuggestionCardState();
}

class _PeopleSuggestionCardState extends State<_PeopleSuggestionCard> {
  static const List<Color> _avatarColors = [
    Color(0xFF8C1D40),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  final Set<String> _dismissedIds = {};
  final Set<String> _followPulseIds = {};
  final Set<String> _followingTransitionIds = {};
  bool _isClosing = false;

  bool _hasAnotherSuggestion(String removedId) => widget.suggestions.any(
    (user) =>
        user.id != removedId &&
        !userState.isFollowingUser(user.id) &&
        !_dismissedIds.contains(user.id),
  );

  Future<void> _closeSection() async {
    if (_isClosing) return;
    setState(() => _isClosing = true);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (mounted) widget.onFollowed();
  }

  @override
  Widget build(BuildContext context) {
    // Re-check live follow state so newly followed people disappear, but keep
    // them around briefly while their card animates out.
    final shown = widget.suggestions
        .where(
          (user) =>
              (!userState.isFollowingUser(user.id) ||
                  _followPulseIds.contains(user.id) ||
                  _followingTransitionIds.contains(user.id)) &&
              !_dismissedIds.contains(user.id),
        )
        .take(8)
        .toList();

    if (shown.isEmpty) return const SizedBox.shrink();

    final content = Container(
      key: const ValueKey('people-suggestion-content'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: AppColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Icon(
                  Icons.people_outline,
                  size: 17,
                  color: AppColors.primaryRed,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!.suggestedForYou,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 225,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: shown.length,
              separatorBuilder: (_, i) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final u = shown[i];
                final color = _avatarColors[i % _avatarColors.length];
                final displayName = userState.displayNameFor(u.id, u.name);
                final followsMe = peopleService.cachedFollowerIds.contains(
                  u.id,
                );
                final isFollowingTransition = _followingTransitionIds.contains(
                  u.id,
                );
                final isFollowPulsing = _followPulseIds.contains(u.id);

                final mutualIds = peopleService.mutualFollowerIdsFor(u.id);
                final mutualCount = mutualIds.length;
                final mutualUsers = peopleService.peopleByIds(
                  mutualIds.take(3),
                );

                return SizedBox(
                  width: 148,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final scale = Tween<double>(begin: 0.96, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: scale, child: child),
                      );
                    },
                    child: AnimatedSlide(
                      key: ValueKey('person-suggestion-${u.id}'),
                      offset: isFollowingTransition
                          ? const Offset(0.14, 0)
                          : Offset.zero,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: isFollowingTransition ? 0 : 1,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(9, 10, 9, 10),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Stack(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            UserProfileScreen(user: u),
                                      ),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FollowAvatarPulse(
                                            active: isFollowPulsing,
                                            color: AppColors.primaryRed,
                                            child: UserAvatar(
                                              userId: u.id,
                                              name: u.name,
                                              size: 72,
                                              fontSize: 27,
                                              backgroundColor: color.withValues(
                                                alpha: 0.15,
                                              ),
                                              textColor: color,
                                            ),
                                          ),
                                          if (mutualCount > 0) ...[
                                            const SizedBox(height: 6),
                                            MutualFollowersBadge(
                                              suggestedUserId: u.id,
                                              mutualUsers: mutualUsers,
                                              mutualCount: mutualCount,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            UserProfileScreen(user: u),
                                      ),
                                    ),
                                    child: Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  const SizedBox(height: 8),
                                  UserFollowButton(
                                    userId: u.id,
                                    size: 'small',
                                    followLabel: followsMe
                                        ? AppLocalizations.of(
                                            context,
                                          )!.followBack
                                        : null,
                                    onTap: () async {
                                      final myId = authService.isStudentSession
                                          ? authService.currentUser?.id ?? ''
                                          : '';
                                      if (myId.isEmpty ||
                                          isFollowingTransition) {
                                        return;
                                      }
                                      final follow = !userState.isFollowingUser(
                                        u.id,
                                      );
                                      if (follow) {
                                        setState(
                                          () => _followPulseIds.add(u.id),
                                        );
                                      }
                                      userState.setFollowingUser(u.id, follow);
                                      userPrefsService.save(myId);
                                      try {
                                        if (follow) {
                                          await Future<void>.delayed(
                                            const Duration(milliseconds: 240),
                                          );
                                          if (mounted) {
                                            setState(() {
                                              _followPulseIds.remove(u.id);
                                              _followingTransitionIds.add(u.id);
                                            });
                                          }
                                          await Future<void>.delayed(
                                            const Duration(milliseconds: 220),
                                          );
                                          if (mounted) {
                                            if (_hasAnotherSuggestion(u.id)) {
                                              setState(
                                                () => _followingTransitionIds
                                                    .remove(u.id),
                                              );
                                              widget.onFollowed();
                                            } else {
                                              await _closeSection();
                                            }
                                          }
                                        } else {
                                          widget.onFollowed();
                                        }
                                        await peopleService.setFollowing(
                                          followerId: myId,
                                          followingId: u.id,
                                          follow: follow,
                                        );
                                        userPrefsService.save(myId);
                                      } catch (_) {
                                        userState.setFollowingUser(
                                          u.id,
                                          !follow,
                                        );
                                        userPrefsService.save(myId);
                                        if (mounted) {
                                          setState(() {
                                            _followPulseIds.remove(u.id);
                                            _followingTransitionIds.remove(
                                              u.id,
                                            );
                                          });
                                          widget.onFollowed();
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                              Positioned(
                                top: -2,
                                right: -2,
                                child: GestureDetector(
                                  onTap: () {
                                    if (_hasAnotherSuggestion(u.id)) {
                                      setState(() => _dismissedIds.add(u.id));
                                    } else {
                                      _closeSection();
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: AppColors.card.withValues(
                                        alpha: 0.85,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1),
        ],
      ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: AlignmentDirectional.topStart,
            child: child,
          ),
        ),
        child: _isClosing
            ? const SizedBox(key: ValueKey('people-suggestion-closed'))
            : content,
      ),
    );
  }
}

// ─── Trending Event Card ──────────────────────────────────────────────────────

class _TrendingEventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onUpdate;

  static const List<Color> _colors = [
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  const _TrendingEventCard({
    super.key,
    required this.event,
    required this.onUpdate,
  });

  void _showDetail(BuildContext context, Color color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(event: event, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final club = _clubById(event.clubId);
    if (club == null) return const SizedBox.shrink();
    final idx = clubOrdinal(club.id);
    final color = _colors[idx % _colors.length];
    final dt = event.dateTime;
    final daysAway = dt.difference(DateTime.now()).inDays;
    final timeLabel = daysAway == 0
        ? AppLocalizations.of(context)!.today
        : daysAway == 1
        ? AppLocalizations.of(context)!.tomorrow
        : '${DateFormat.MMM(localeService.languageCode).format(dt)} ${dt.day}';
    return GestureDetector(
      onTap: () => _showDetail(context, color),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: AppColors.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event body
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.all(Radius.circular(14)),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Colour accent + date chip
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.event_rounded,
                                  size: 13,
                                  color: color,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  timeLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (event.location.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.location,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (audienceForEvent(event) != ContentAudience.everyone) ...[
                    const SizedBox(height: 10),
                    ContentAudiencePill(
                      key: ValueKey('content-audience-pill-${event.id}'),
                      audience: audienceForEvent(event),
                      accent: color,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        AppLocalizations.of(context)!.tapForDetails,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded, size: 14, color: color),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

// ─── Club Suggestion Card ─────────────────────────────────────────────────────

class _ClubSuggestionCard extends StatefulWidget {
  final dynamic club;
  final VoidCallback onUpdate;

  const _ClubSuggestionCard({
    super.key,
    required this.club,
    required this.onUpdate,
  });

  @override
  State<_ClubSuggestionCard> createState() => _ClubSuggestionCardState();
}

class _ClubSuggestionCardState extends State<_ClubSuggestionCard> {
  static const List<Color> _colors = [
    Color(0xFF8C1D40),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  @override
  Widget build(BuildContext context) {
    final c = widget.club;
    final idx = clubOrdinal(c.id as String);
    final color = _colors[idx < 0 ? 0 : idx % _colors.length];
    final memberCount = clubMemberCount(c.id as String);
    final matches = personalizationService.interestMatchCount(c.id as String);
    final desc = (c.description as String).isNotEmpty
        ? c.description as String
        : AppLocalizations.of(context)!.discoverClubDescriptionFallback;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClubProfileScreen(club: c, color: color),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: AppColors.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Icon(Icons.explore_rounded, size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.clubMightLike,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
            // Club row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    // Avatar
                    ClubAvatar(
                      clubId: c.id as String,
                      clubName: c.name as String,
                      color: color,
                      imageUrl: c.logoUrl,
                      size: 52,
                      fontSize: 20,
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name as String,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryText,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                matches > 0
                                    ? Icons.auto_awesome_rounded
                                    : Icons.people_outline,
                                size: 13,
                                color: color,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  matches > 0
                                      ? AppLocalizations.of(
                                          context,
                                        )!.membersMatchInterests(memberCount)
                                      : AppLocalizations.of(
                                          context,
                                        )!.membersCount(memberCount),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: color,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (authService.isStudentSession)
                      ClubFollowButton(clubId: c.id as String),
                  ],
                ),
              ),
            ),
            Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

class _PeopleEngagementSheet extends StatelessWidget {
  final IconData icon;
  final String emptyText;
  final List<User> people;
  final ScrollController scrollController;

  const _PeopleEngagementSheet({
    required this.icon,
    required this.emptyText,
    required this.people,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryRed, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.peopleCount(people.length),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.text,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(
                  Icons.close,
                  color: AppColors.secondaryText,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1),
        Expanded(
          child: people.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: AppColors.secondaryText, size: 40),
                      SizedBox(height: 12),
                      Text(
                        emptyText,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: people.length,
                  separatorBuilder: (_, s) => Divider(height: 1, indent: 60),
                  itemBuilder: (_, i) {
                    final user = people[i];
                    return ListTile(
                      leading: UserAvatar(
                        userId: user.id,
                        name: user.name,
                        size: 40,
                        fontSize: 15,
                      ),
                      title: Text(
                        userState.displayNameFor(user.id, user.name),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.text,
                        ),
                      ),
                      subtitle: Text(
                        user.email,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(user: user),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PeopleEngagementSkeleton extends StatelessWidget {
  final IconData icon;
  final ScrollController scrollController;

  const _PeopleEngagementSkeleton({
    required this.icon,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryRed, size: 20),
              const SizedBox(width: 8),
              SkeletonBox(
                width: 118,
                height: 16,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: 6,
            separatorBuilder: (_, s) =>
                Divider(height: 1, indent: 60, color: AppColors.divider),
            itemBuilder: (_, i) => const _PeopleEngagementSkeletonRow(),
          ),
        ),
      ],
    );
  }
}

class _PeopleEngagementSkeletonRow extends StatelessWidget {
  const _PeopleEngagementSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SkeletonBox.circle(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(
                  width: 140,
                  height: 13,
                  borderRadius: BorderRadius.all(Radius.circular(7)),
                ),
                const SizedBox(height: 8),
                SkeletonBox(
                  width: 190,
                  height: 11,
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewersSheet extends StatefulWidget {
  final String contentId;
  final String title;

  const _ViewersSheet({required this.contentId, required this.title});

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  List<User> _viewers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadViewers();
  }

  Future<void> _loadViewers() async {
    var viewers = viewTracker.viewers(widget.contentId);

    try {
      final remote = await supabaseInteractionService.fetchPostViewers(
        widget.contentId,
      );
      if (remote.isNotEmpty) viewers = remote;
    } catch (_) {
      // Keep local/Hive viewers.
    }

    if (!mounted) return;
    setState(() {
      _viewers = viewers;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _loading
            ? _PeopleEngagementSkeleton(
                icon: Icons.remove_red_eye_outlined,
                scrollController: scrollController,
              )
            : _PeopleEngagementSheet(
                icon: Icons.remove_red_eye_outlined,
                emptyText: AppLocalizations.of(context)!.noViewsYet,
                people: _viewers,
                scrollController: scrollController,
              ),
      ),
    );
  }
}

List<User> _localPostLikers(String postId) {
  final likerIds = likes
      .where((like) => like.postId == postId)
      .map((like) => like.userId)
      .toSet();
  return users.where((user) => likerIds.contains(user.id)).toList();
}

class _LikedByRow extends StatefulWidget {
  final String postId;
  final int likeCount;
  final VoidCallback onTap;

  const _LikedByRow({
    required this.postId,
    required this.likeCount,
    required this.onTap,
  });

  @override
  State<_LikedByRow> createState() => _LikedByRowState();
}

class _LikedByRowState extends State<_LikedByRow> {
  List<User> _likers = const [];

  @override
  void initState() {
    super.initState();
    _refreshPreview();
  }

  @override
  void didUpdateWidget(covariant _LikedByRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId ||
        oldWidget.likeCount != widget.likeCount) {
      _refreshPreview();
    }
  }

  void _refreshPreview() {
    final local = _localPostLikers(widget.postId);
    if (local.isNotEmpty) {
      _likers = local;
      return;
    }

    unawaited(_loadRemotePreview());
  }

  Future<void> _loadRemotePreview() async {
    try {
      final remote = await supabaseInteractionService.fetchPostLikerPreview(
        widget.postId,
      );
      if (mounted && remote.isNotEmpty) setState(() => _likers = remote);
    } catch (_) {
      // A count-only fallback remains available while offline.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.likeCount <= 0) return const SizedBox.shrink();

    final liker = _likers.isEmpty ? null : _likers.first;
    final displayName = liker == null
        ? null
        : userState.displayNameFor(liker.id, liker.name);
    final remaining = math.max(0, widget.likeCount - 1);

    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.likesCount(widget.likeCount),
      child: GestureDetector(
        key: ValueKey('post-liked-by-${widget.postId}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.divider),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: liker == null
                      ? ColoredBox(
                          color: AppColors.lightRed,
                          child: Icon(
                            Icons.favorite_rounded,
                            size: 14,
                            color: AppColors.primaryRed,
                          ),
                        )
                      : IgnorePointer(
                          child: UserAvatar(
                            userId: liker.id,
                            name: displayName!,
                            size: 24,
                            fontSize: 10,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    key: ValueKey('${liker?.id}-${widget.likeCount}'),
                    displayName == null
                        ? AppLocalizations.of(
                            context,
                          )!.likesCount(widget.likeCount)
                        : remaining > 0
                        ? S.likedByOthers(displayName, remaining)
                        : S.likedBy(displayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikersSheet extends StatefulWidget {
  final String postId;

  const _LikersSheet({required this.postId});

  @override
  State<_LikersSheet> createState() => _LikersSheetState();
}

class _LikersSheetState extends State<_LikersSheet> {
  List<User> _likers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _likers = _localPostLikers(widget.postId);
    _loading = _likers.isEmpty;
    unawaited(_loadLikers());
  }

  Future<void> _loadLikers() async {
    var likers = _localPostLikers(widget.postId);

    try {
      final remote = await supabaseInteractionService.fetchPostLikers(
        widget.postId,
      );
      if (remote.isNotEmpty) likers = remote;
    } catch (_) {
      // Keep local/mock likers.
    }

    if (!mounted) return;
    setState(() {
      _likers = likers;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Container(
        key: ValueKey('post-likers-sheet-${widget.postId}'),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: _loading
            ? _PeopleEngagementSkeleton(
                icon: Icons.favorite_rounded,
                scrollController: scrollController,
              )
            : _PeopleEngagementSheet(
                icon: Icons.favorite_rounded,
                emptyText: AppLocalizations.of(context)!.noLikesYet,
                people: _likers,
                scrollController: scrollController,
              ),
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

const List<Color> _clubColors = [
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

String _timeAgo(BuildContext context, DateTime dt) {
  final l10n = AppLocalizations.of(context)!;
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return l10n.minutesAgoSuffix(diff.inMinutes);
  if (diff.inHours < 24) return l10n.hoursAgoSuffix(diff.inHours);
  return l10n.daysAgoSuffix(diff.inDays);
}

/// Copies a deep link for the post/event to the clipboard and records the
/// share (messaging was removed, so sharing is link-based).
void _openShareSheet(
  BuildContext context,
  String targetId,
  VoidCallback onShared, {
  bool isEvent = false,
}) {
  final currentUser = authService.currentUser;
  if (!authService.isStudentSession || currentUser == null) return;

  Clipboard.setData(
    ClipboardData(text: 'kuclubs://${isEvent ? 'event' : 'post'}/$targetId'),
  );

  final alreadyShared = shares.any(
    (s) => s.targetId == targetId && s.userId == currentUser.id,
  );
  if (!alreadyShared) {
    shares.add(
      Share(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        targetId: targetId,
        userId: currentUser.id,
        createdAt: DateTime.now(),
      ),
    );
    contentStore.scheduleSave('shares');
    onShared();
  }

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          isEvent
              ? AppLocalizations.of(context)!.eventLinkCopied
              : AppLocalizations.of(context)!.postLinkCopied,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
}

/// True only when the current session belongs to an admin of [clubId].
/// Ensures analytics and moderation controls are never shown for other clubs.
bool _isOwnerOfClub(String clubId) {
  final admin = authService.currentAdmin;
  if (admin == null) return false;
  final club = clubForId(clubId);
  if (club == null) return false;
  return clubIsManagedByAdmin(club, admin.id);
}

// ─── Post Card ────────────────────────────────────────────────────────────────

class _PostCard extends StatefulWidget {
  final NewsPost post;
  final double score;
  final int rank;

  const _PostCard({
    super.key,
    required this.post,
    required this.score,
    required this.rank,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _likeButtonScale;
  bool _showHeart = false;
  double _photoAspectRatio = 1;
  String? _aspectProbeKey;

  @override
  void initState() {
    super.initState();
    _heartController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed) {
            if (mounted && _showHeart) setState(() => _showHeart = false);
            _heartController.reset();
          }
        });
    _likeButtonScale = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 1, end: 1.28), weight: 34),
        TweenSequenceItem(tween: Tween(begin: 1.28, end: 0.92), weight: 28),
        TweenSequenceItem(tween: Tween(begin: 0.92, end: 1), weight: 38),
      ],
    ).animate(CurvedAnimation(parent: _heartController, curve: Curves.easeOut));
    // Recording a view notifies the engagement bars that are already mounted.
    // Defer that notification until this sliver's first frame is complete;
    // notifying synchronously while sibling cards are still mounting causes
    // Flutter's "setState() or markNeedsBuild() called during build" failure.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId =
          authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
      viewTracker.recordView(widget.post.id, userId, syncRemote: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _probePhotoAspectRatio();
  }

  @override
  void didUpdateWidget(covariant _PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.imagePath != widget.post.imagePath) {
      _aspectProbeKey = null;
      _photoAspectRatio = 1;
      _probePhotoAspectRatio();
    }
  }

  void _probePhotoAspectRatio() {
    final path = widget.post.imagePath?.trim() ?? '';
    if (_aspectProbeKey == path) return;
    _aspectProbeKey = path;

    if (path.isEmpty) {
      _photoAspectRatio = 1;
      return;
    }
    if (path.startsWith('tpl:')) {
      _photoAspectRatio = _portraitFeedAspectRatio;
      return;
    }

    if (path.startsWith('https://') || path.startsWith('http://')) {
      _photoAspectRatio = 1;
      return;
    }

    _photoAspectRatio = imageAspectRatioFromFile(File(path)) ?? 1;
  }

  void _onPhotoAspectRatio(double aspectRatio) {
    if (!mounted || !aspectRatio.isFinite || aspectRatio <= 0) return;
    if ((_photoAspectRatio - aspectRatio).abs() <= 0.001) return;
    setState(() => _photoAspectRatio = aspectRatio);
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _doubleTapLike() {
    if (!authService.isStudentSession) return;
    ensurePostLiked(widget.post.id);
    HapticFeedback.mediumImpact();
    setState(() => _showHeart = true);
    _heartController.forward(from: 0);
  }

  void _toggleLike() {
    if (!authService.isStudentSession) return;
    final becomingLiked = !userState.isLiked(widget.post.id);
    togglePostLike(widget.post.id);
    if (becomingLiked) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    if (!MediaQuery.disableAnimationsOf(context)) {
      _heartController.forward(from: 0);
    }
    setState(() {});
  }

  void _showLikersSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 420),
        reverseDuration: Duration(milliseconds: 260),
      ),
      builder: (_) => _LikersSheet(postId: widget.post.id),
    );
  }

  Future<void> _sharePostToChat() async {
    final currentUser = authService.currentUser;
    if (!authService.isStudentSession || currentUser == null) return;
    final threadId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PostShareSheet(
        post: widget.post,
        currentUserId: currentUser.id,
        onShared: () {
          if (mounted) setState(() {});
        },
      ),
    );
    if (!mounted || threadId == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(S.postShared),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _changePostAudience() async {
    final picked = await showContentAudienceSheet(
      context,
      current: audienceForPost(widget.post),
      surface: AppColors.card,
      border: AppColors.divider,
      text: AppColors.text,
      muted: AppColors.secondaryText,
      accent: AppColors.primaryRed,
    );
    if (!mounted || picked == null) return;
    await updatePostAudience(widget.post, picked);
  }

  void _showPostOptions() {
    final canDelete = contentStore.canDeletePost(
      widget.post.id,
      authService.currentAdmin?.id ?? '',
    );
    // There is no post editor in this app, so retargeting an already-published
    // post lives here rather than behind an edit screen.
    final canRetarget = canChooseAudienceForClub(widget.post.clubId);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget tile({
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          Color? color,
        }) {
          return ListTile(
            leading: Icon(icon, color: color ?? AppColors.text),
            title: Text(
              label,
              style: TextStyle(
                color: color ?? AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
              const SizedBox(height: 8),
              if (canRetarget)
                tile(
                  icon: Icons.visibility_outlined,
                  label: S.audienceChangeAction,
                  onTap: () => unawaited(_changePostAudience()),
                ),
              if (canDelete)
                tile(
                  icon: Icons.delete_outline_rounded,
                  label: AppLocalizations.of(sheetContext)!.deletePostAction,
                  color: Colors.red,
                  onTap: _confirmDeletePost,
                ),
              tile(
                icon: Icons.flag_outlined,
                label: AppLocalizations.of(context)!.reportPost,
                color: AppColors.primaryRed,
                onTap: _reportPost,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeletePost() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          AppLocalizations.of(dialogContext)!.deletePost,
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          AppLocalizations.of(dialogContext)!.deletePostFeedBody,
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              AppLocalizations.of(dialogContext)!.cancel,
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
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await supabasePostService.deletePost(widget.post);
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.couldNotDeletePostSupabase,
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                return;
              }
              final deleted = contentStore.deletePost(
                widget.post.id,
                authService.currentAdmin?.id ?? '',
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      deleted
                          ? AppLocalizations.of(
                              context,
                            )!.postDeletedConfirmation
                          : AppLocalizations.of(
                              context,
                            )!.onlyOwningClubCanDelete,
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
            child: Text(AppLocalizations.of(dialogContext)!.delete),
          ),
        ],
      ),
    );
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
    ScaffoldMessenger.of(context)
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
    final club = _clubById(widget.post.clubId);
    if (club == null) return const SizedBox.shrink();
    final clubColor = _colorForClub(club.id);
    final likeCount = postLikeCount(widget.post.id);
    final shareCount = postShareCount(widget.post.id);
    final isLiked = userState.isLiked(widget.post.id);
    final isStudent = authService.isStudentSession;
    final ownContent = _isOwnerOfClub(widget.post.clubId);
    final hasImage =
        widget.post.imagePath != null && widget.post.imagePath!.isNotEmpty;
    final mediaHeight = _homeFeedPhotoHeight(
      MediaQuery.sizeOf(context).width,
      aspectRatio: _photoAspectRatio,
    );
    final caption = ExpandablePostCaption(
      key: ValueKey('home-feed-caption-${widget.post.id}'),
      authorName: '',
      caption: widget.post.content,
      captionStyle: TextStyle(
        color: AppColors.text,
        fontSize: 14.5,
        height: 1.45,
      ),
      moreStyle: TextStyle(
        color: AppColors.primaryRed,
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
      ),
    );

    // Keep the identity in a compact header so Home-feed media can use the
    // full card width. Captions for photo posts deliberately follow the media.
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(
            color: AppColors.divider.withValues(alpha: 0.7),
            width: 0.6,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + club identity + time, with follow + more.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ClubProfileScreen(club: club, color: clubColor),
                  ),
                ),
                child: ClubAvatar(
                  clubId: club.id,
                  clubName: club.name,
                  color: clubColor,
                  imageUrl: club.logoUrl,
                  size: 44,
                  fontSize: 18,
                  shape: 'circle',
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ClubProfileScreen(club: club, color: clubColor),
                        ),
                      ),
                      child: Text(
                        club.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: AppColors.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _timeAgo(context, widget.post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isStudent) ClubFollowButton(clubId: club.id, size: 'small'),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showPostOptions,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
          // ── Audience badge — only for restricted posts ──
          if (audienceForPost(widget.post) != ContentAudience.everyone) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ContentAudiencePill(
                key: ValueKey('content-audience-pill-${widget.post.id}'),
                audience: audienceForPost(widget.post),
                accent: clubColor,
              ),
            ),
          ],
          // ── Announcement banner ──
          if (widget.post.isAnnouncement) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: clubColor.withValues(alpha: 0.09),
                borderRadius: BorderRadius.all(Radius.circular(10)),
                border: Border.all(color: clubColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign_rounded, size: 15, color: clubColor),
                  const SizedBox(width: 6),
                  Text(
                    S.announcement.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: clubColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Text-only posts keep their copy directly below the header.
          if (!hasImage && widget.post.content.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            caption,
          ],
          // ── Poll ──
          if (widget.post.poll != null)
            PollCard(post: widget.post, accent: clubColor),
          // ── Media (full-card width on Home) ──
          if (hasImage) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: mediaHeight,
              child: OverflowBox(
                alignment: Alignment.center,
                minWidth: MediaQuery.sizeOf(context).width,
                maxWidth: MediaQuery.sizeOf(context).width,
                child: GestureDetector(
                  key: ValueKey('home-feed-photo-${widget.post.id}'),
                  onDoubleTap: isStudent ? _doubleTapLike : null,
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width,
                    height: mediaHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        buildPostBanner(
                          imagePath: widget.post.imagePath,
                          fallbackColor: clubColor,
                          fallbackLetter: club.name[0],
                          height: mediaHeight,
                          onAspectRatio: _onPhotoAspectRatio,
                        ),
                        if (_showHeart)
                          ScaleTransition(
                            scale: Tween(begin: 0.5, end: 1.4).animate(
                              CurvedAnimation(
                                parent: _heartController,
                                curve: Curves.elasticOut,
                              ),
                            ),
                            child: Icon(
                              Icons.favorite,
                              color: Colors.white,
                              size: 72,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.post.content.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              caption,
            ],
          ],
          // ── Engagement stats (own-club admin only) ──
          if (ownContent) ...[
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: viewTracker,
              builder: (context, _) => _EngagementBar(
                likes: likeCount,
                shares: shareCount,
                score: widget.score,
                views: viewTracker.viewCount(widget.post.id),
                onViewTap: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => _ViewersSheet(
                    contentId: widget.post.id,
                    title: AppLocalizations.of(context)!.postViewersTitle,
                  ),
                ),
                onLikeTap: _showLikersSheet,
              ),
            ),
          ],
          const SizedBox(height: 4),
          // ── Action row (X-style) ──
          // Club admins get no like/share controls on their own posts, but
          // they still need to read the discussion underneath them, so the
          // comment button appears for them too.
          if (isStudent || ownContent)
            Row(
              children: [
                if (isStudent) ...[
                  _twAction(
                    icon: isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    count: likeCount > 0 ? likeCount : null,
                    color: isLiked
                        ? AppColors.primaryRed
                        : AppColors.secondaryText,
                    iconScale: _likeButtonScale,
                    onTap: _toggleLike,
                  ),
                  const SizedBox(width: 18),
                ],
                // Scoped to the badge: commentStore notifies whenever any
                // post's comments load, and rebuilding the whole card for a
                // number would undo the feed's scroll work.
                ListenableBuilder(
                  listenable: commentStore,
                  builder: (context, _) {
                    final count = commentStore.countFor(widget.post.id);
                    return _twAction(
                      key: ValueKey('home-feed-comment-${widget.post.id}'),
                      icon: Icons.mode_comment_outlined,
                      count: count > 0 ? count : null,
                      color: AppColors.secondaryText,
                      onTap: _openComments,
                    );
                  },
                ),
                if (isStudent) ...[
                  const SizedBox(width: 18),
                  _twAction(
                    icon: Icons.send_outlined,
                    count: null,
                    color: AppColors.secondaryText,
                    onTap: _sharePostToChat,
                  ),
                ],
              ],
            ),
          if (likeCount > 0)
            _LikedByRow(
              postId: widget.post.id,
              likeCount: likeCount,
              onTap: _showLikersSheet,
            ),
        ],
      ),
    );
  }

  void _openComments() {
    unawaited(
      showCommentsSheet(
        context,
        post: widget.post,
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  // X-style action: an icon with an optional count beside it.
  Widget _twAction({
    Key? key,
    required IconData icon,
    int? count,
    required Color color,
    required VoidCallback onTap,
    Animation<double>? iconScale,
  }) {
    Widget iconWidget = AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.72, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Icon(icon, key: ValueKey(icon), size: 19, color: color),
    );
    if (iconScale != null) {
      iconWidget = ScaleTransition(
        key: const ValueKey('home-feed-like-heart-motion'),
        scale: iconScale,
        child: iconWidget,
      );
    }

    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.all(Radius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            RollingCount(
              value: count,
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Event Card (in feed) ─────────────────────────────────────────────────────

class _EventCard extends StatefulWidget {
  final Event event;
  final double score;
  final int rank;
  final VoidCallback onUpdate;

  const _EventCard({
    super.key,
    required this.event,
    required this.score,
    required this.rank,
    required this.onUpdate,
  });

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  bool? _lastAttending;

  @override
  void initState() {
    super.initState();
    final userId =
        authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';
    rsvpStore.seed(
      widget.event.id,
      widget.event.attendeeUserIds.contains(userId),
    );
    _lastAttending = rsvpStore.isAttending(widget.event.id);
    rsvpStore.addListener(_onRsvpChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      viewTracker.recordView(widget.event.id, userId);
    });
  }

  @override
  void dispose() {
    rsvpStore.removeListener(_onRsvpChanged);
    super.dispose();
  }

  void _onRsvpChanged() {
    final current = rsvpStore.isAttending(widget.event.id);
    if (current == _lastAttending) return; // different event changed, skip
    _lastAttending = current;
    if (mounted) {
      setState(() {});
      widget.onUpdate();
    }
  }

  void _openDetails(Color color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(event: widget.event, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final club = _clubById(widget.event.clubId);
    if (club == null) return const SizedBox.shrink();
    final clubColor = _colorForClub(club.id);
    final dt = widget.event.dateTime;
    final shareCount = postShareCount(widget.event.id);

    final daysAway = dt.difference(DateTime.now()).inDays;
    final daysLabel = daysAway == 0
        ? AppLocalizations.of(context)!.today
        : daysAway == 1
        ? AppLocalizations.of(context)!.tomorrow
        : AppLocalizations.of(context)!.inDaysCount(daysAway);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetails(clubColor),
      child: Container(
        color: AppColors.card,
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ClubProfileScreen(club: club, color: clubColor),
                      ),
                    ),
                    child: ClubAvatar(
                      clubId: club.id,
                      clubName: club.name,
                      color: clubColor,
                      imageUrl: club.logoUrl,
                      size: 38,
                      fontSize: 16,
                      shape: 'circle',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ClubProfileScreen(
                                      club: club,
                                      color: clubColor,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  club.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.text,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          daysLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primaryRed,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (authService.isStudentSession)
                    ClubFollowButton(clubId: club.id, size: 'small'),
                ],
              ),
            ),

            // ── Event banner ──
            SizedBox(
              width: double.infinity,
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EventCoverImage(
                    event: widget.event,
                    color: clubColor,
                    width: double.infinity,
                    height: 160,
                    cacheWidth: 700,
                    cacheHeight: 320,
                  ),
                  // The badge goes over the banner rather than into the
                  // header row: this card's header already carries the club
                  // name, the days-away label and a follow button.
                  Positioned(
                    left: 16,
                    top: 12,
                    child: ContentAudiencePill.onMedia(
                      key: ValueKey('content-audience-pill-${widget.event.id}'),
                      audience: audienceForEvent(widget.event),
                    ),
                  ),
                  // Big date in background
                  Positioned(
                    right: 16,
                    top: 12,
                    child: Text(
                      '${dt.day}',
                      style: TextStyle(
                        fontSize: 80,
                        fontWeight: FontWeight.w900,
                        color: context.semanticColors.onMedia.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        DynamicContrastText(
                          '${_monthAbbr(dt.month)} ${dt.day}  ·  ${_fmt12(dt)}',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        const SizedBox(height: 8),
                        DynamicContrastText(
                          widget.event.title,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (authService.isStudentSession)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: RsvpButton(
                        eventId: widget.event.id,
                        color: AppColors.primaryRed,
                        isPast: !widget.event.endTime.isAfter(DateTime.now()),
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _ActionBtn(
                      icon: Icons.send_outlined,
                      color: AppColors.text,
                      onTap: () =>
                          _openShareSheet(context, widget.event.id, () {
                            setState(() {});
                            widget.onUpdate();
                          }, isEvent: true),
                    ),
                    const Spacer(),
                    _ActionBtn(
                      icon: userState.isSaved(widget.event.id)
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: userState.isSaved(widget.event.id)
                          ? AppColors.primaryRed
                          : AppColors.text,
                      onTap: () {
                        setState(() => userState.toggleSave(widget.event.id));
                        userPrefsService.save(
                          authService.isStudentSession
                              ? authService.currentUser?.id ?? ''
                              : '',
                        );
                      },
                    ),
                  ],
                ),
              ),

            // ── Engagement stats (own-club admin only) ──
            if (_isOwnerOfClub(widget.event.clubId)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ListenableBuilder(
                  listenable: viewTracker,
                  builder: (context, _) => _EngagementBar(
                    likes: 0,
                    shares: shareCount,
                    score: widget.score,
                    views: viewTracker.viewCount(widget.event.id),
                    onViewTap: () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => _ViewersSheet(
                        contentId: widget.event.id,
                        title: AppLocalizations.of(context)!.eventViewersTitle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),

            // ── Description ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${club.name}  ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                        fontSize: 13,
                      ),
                    ),
                    TextSpan(
                      text: widget.event.description,
                      style: TextStyle(color: AppColors.text, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  String _monthAbbr(int m) =>
      DateFormat.MMM(localeService.languageCode).format(DateTime(2024, m));

  String _fmt12(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

// ─── Engagement Bar ───────────────────────────────────────────────────────────

class _EngagementBar extends StatelessWidget {
  final int likes;
  final int shares;
  final int views;
  final double score;
  final VoidCallback? onViewTap;
  final VoidCallback? onLikeTap;

  const _EngagementBar({
    required this.likes,
    required this.shares,
    required this.score,
    this.views = 0,
    this.onViewTap,
    this.onLikeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (views > 0) ...[
          GestureDetector(
            onTap: onViewTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.remove_red_eye_outlined,
                  size: 13,
                  color: AppColors.secondaryText,
                ),
                const SizedBox(width: 3),
                Text(
                  AppLocalizations.of(context)!.viewsCount(views),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryText,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (likes > 0) ...[
          if (views > 0) const SizedBox(width: 10),
          GestureDetector(
            onTap: onLikeTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite, size: 13, color: Colors.pink),
                const SizedBox(width: 3),
                Text(
                  AppLocalizations.of(context)!.likesCount(likes),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                    decoration: onLikeTap == null
                        ? TextDecoration.none
                        : TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (shares > 0) ...[
          const SizedBox(width: 10),
          Icon(Icons.send, size: 13, color: Color(0xFF2E7D32)),
          const SizedBox(width: 3),
          Text(
            AppLocalizations.of(context)!.sharesCount(shares),
            style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
          ),
        ],
      ],
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: 26),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

// ─── Event Rail Card ──────────────────────────────────────────────────────────

class _EventRailCard extends StatefulWidget {
  final Event event;
  const _EventRailCard({super.key, required this.event});

  @override
  State<_EventRailCard> createState() => _EventRailCardState();
}

class _EventRailCardState extends State<_EventRailCard> {
  static const _colors = [
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
    Color(0xFF512DA8),
    Color(0xFFAD1457),
  ];

  @override
  Widget build(BuildContext context) {
    final ev = widget.event;
    final club = clubForId(ev.clubId);
    if (club == null) return const SizedBox.shrink();
    final idx = clubOrdinal(club.id);
    final color = _colors[idx < 0 ? 0 : idx % _colors.length];
    final now = DateTime.now();
    final isLive = ev.dateTime.isBefore(now) && ev.endTime.isAfter(now);
    final dateTimeLabel = isLive
        ? '${AppLocalizations.of(context)!.liveNowLabel} · ${_time24(ev.dateTime)}'
        : '${_weekdayShort(ev.dateTime)}. ${_time24(ev.dateTime)}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(event: ev, color: color),
        ),
      ),
      child: Container(
        width: 218,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.all(Radius.circular(19)),
          border: Border.all(
            color: AppColors.primaryRed.withValues(
              alpha: themeService.isDark ? 0.46 : 0.22,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: themeService.isDark ? 0.24 : 0.06,
              ),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 108,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EventCoverImage(
                    event: ev,
                    color: color,
                    width: double.infinity,
                    height: 108,
                    cacheWidth: 440,
                    cacheHeight: 220,
                  ),
                  Positioned(
                    left: 9,
                    top: 8,
                    child: DynamicContrastText(
                      dateTimeLabel,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                  // The text area below is a fixed 70px holding a title and a
                  // location line, so the badge goes on the cover instead.
                  Positioned(
                    right: 9,
                    top: 8,
                    child: ContentAudiencePill.onMedia(
                      key: ValueKey('content-audience-pill-${ev.id}'),
                      audience: audienceForEvent(ev),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        letterSpacing: -0.35,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: AppColors.secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            ev.location,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.secondaryText,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time24(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _weekdayShort(DateTime dt) =>
      DateFormat.E(localeService.languageCode).format(dt);
}

// ─── Pulsing dot (live indicator) ─────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.45,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

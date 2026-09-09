import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/theme_service.dart';
import '../models/club.dart';
import '../models/user.dart';
import '../services/academic_year_options.dart';
import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/guest_world.dart' show kGuestIdPrefix;
import '../services/lazy_content_loader.dart';
import '../services/mock_data.dart';
import '../services/people_service.dart';
import '../services/personalization_service.dart'
    show kAcademicPrograms, normalizeAcademicProgramName;
import '../services/moderation_service.dart';
import '../services/club_follow_helper.dart';
import '../services/user_state.dart';
import '../services/user_prefs_service.dart';
import '../onboarding/onboarding_anchors.dart';
import '../widgets/club_avatar.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/search_design.dart';
import '../widgets/search_filter_sheet.dart';
import '../widgets/user_avatar.dart';
import '../widgets/app_pressable.dart';
import 'club_profile_screen.dart';
import 'user_profile_screen.dart';

/// Student search.
///
/// Built from the **STUDENT SEARCH** section of the ClubUp-Desings Figma file
/// (`clubup-search`, `search-filter`, `clubup-filter`, `clubup-major`). The
/// handoff replaces the old Discover Clubs / Find People tab pair with a
/// single scrolling page: one search field that covers both sides of the
/// directory, three discovery sections underneath it, and a Filters sheet
/// behind the field's slider icon that chooses which side you are searching.
///
/// Colours and type come from [SearchColors] / [figtree] rather than
/// `AppColors`, because the handoff runs on a different palette from the rest
/// of the app. See `lib/widgets/search_design.dart`.
class ExploreScreen extends StatefulWidget {
  /// Retained from the tabbed layout: 0 opens the Clubs side of the directory,
  /// 1 opens Students. The tabs themselves are gone, but callers still address
  /// the two sides through this index.
  final int initialTabIndex;

  const ExploreScreen({super.key, this.initialTabIndex = 0});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();

  static String categoryFor(BuildContext context, Club club) {
    final category = club.categoryName?.trim();
    if (category != null && category.isNotEmpty) return category;

    final n = club.name.toLowerCase();
    bool has(List<String> keys) => keys.any(n.contains);

    if (has([
      'mühendis',
      'bilgisayar',
      'aiche',
      'kumech',
      'ies',
      'kuswe',
      'kuacm',
    ])) {
      return AppLocalizations.of(context)!.categoryEngineering;
    }
    if (has(['ekonomi', 'girişimcilik', 'işletme', 'pazarlama', 'politik'])) {
      return AppLocalizations.of(context)!.categoryBusiness;
    }
    if (has(['dağcılık', 'fenerbahçe', 'kartal', 'spor'])) {
      return AppLocalizations.of(context)!.categorySports;
    }
    if (has([
      'sanat',
      'dans',
      'ebru',
      'fotoğraf',
      'folklör',
      'müzik',
      'müzikal',
      'orkestra',
      'resim',
      'sinema',
      'tiyatro',
      'radyo',
      'thm',
      'koro',
    ])) {
      return AppLocalizations.of(context)!.categoryArts;
    }
    if (has([
      'gönüllü',
      'kadın',
      'kuir',
      'kürt',
      'sosyal',
      'düşünce',
      'dayanışma',
    ])) {
      return AppLocalizations.of(context)!.categorySocial;
    }
    // Felsefe, Hukuk, Tarih, Tıp, Hemşirelik, Nöroloji, Münazara, Beşeri,
    // Türk Araştırmaları, Arkeoloji, Atatürkçü … and anything else.
    return AppLocalizations.of(context)!.categoryAcademic;
  }
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  late SearchFilters _filters = SearchFilters(
    scope: widget.initialTabIndex == 1
        ? SearchScope.students
        : SearchScope.clubs,
  );
  bool _directoryScopeApplied = false;

  // People state
  String? _peopleFeedback;
  bool _peopleFeedbackIsFollowing = false;
  int _peopleFeedbackVersion = 0;
  List<User> _people = const [];
  final List<String> _suggestedProfileIds = [];
  bool _peopleLoading = false;
  bool _peopleHasError = false;

  // Palette for the colored monograms (mirrors the design's per-item hues).
  static const List<Color> _hues = [
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
    Color(0xFF512DA8),
    Color(0xFFAD1457),
  ];

  Color _hueFor(int index) => _hues[index.abs() % _hues.length];

  String get _myId =>
      authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';

  bool get _canFollowPeople => authService.isStudentSession;

  bool get _searchingClubs => _filters.scope == SearchScope.clubs;

  /// With no explicit scope from Filters, the search field covers the whole
  /// directory. This is also the state restored by Reset.
  bool get _searchingAllDirectories =>
      !_directoryScopeApplied && _filters.isEmpty && _query.trim().isNotEmpty;

  /// The discovery sections give way to a scope-only result list as soon as
  /// the student searches or applies the Filters sheet. Scope counts as an
  /// applied choice even when no category, major, or year is selected.
  bool get _showingResults =>
      _directoryScopeApplied || _query.trim().isNotEmpty || !_filters.isEmpty;

  @override
  void initState() {
    super.initState();
    localeService.addListener(_onLocaleChanged);
    themeService.addListener(_onLocaleChanged);
    _loadClubContent();
    _loadPeople();
  }

  @override
  void dispose() {
    _searchController.dispose();
    localeService.removeListener(_onLocaleChanged);
    themeService.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadClubContent() async {
    try {
      await lazyContentLoader.ensureContentLoaded();
      if (mounted) setState(() {});
    } catch (_) {
      // Keep local seed clubs visible if Supabase content is unreachable.
    }
  }

  // ─── Club data ───────────────────────────────────────────────────────────

  List<Club> get _visibleClubs =>
      clubs.where((c) => !moderationService.isClubBlocked(c.id)).toList();

  /// Most recent post for a club, used by the "Recently Active" sort. Falls
  /// back to when the club itself was created so every club still orders.
  DateTime _lastActive(Club club) {
    DateTime? latest;
    for (final post in newsPosts) {
      if (post.clubId != club.id) continue;
      if (latest == null || post.createdAt.isAfter(latest)) {
        latest = post.createdAt;
      }
    }
    return latest ?? club.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _compareClubsByMembers(Club a, Club b) {
    final byMembers = clubMemberCount(b.id).compareTo(clubMemberCount(a.id));
    if (byMembers != 0) return byMembers;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  List<Club> get _resultClubs {
    final q = _query.toLowerCase().trim();
    final categories = _filters.categories;

    final list = _visibleClubs.where((c) {
      final category = ExploreScreen.categoryFor(context, c);
      if (categories.isNotEmpty && !categories.contains(category)) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q) ||
          (c.shortName?.toLowerCase().contains(q) ?? false) ||
          (c.email?.toLowerCase().contains(q) ?? false) ||
          category.toLowerCase().contains(q);
    }).toList();

    switch (_filters.clubSort) {
      case ClubSort.members:
        list.sort(_compareClubsByMembers);
      case ClubSort.recentlyActive:
        list.sort((a, b) => _lastActive(b).compareTo(_lastActive(a)));
    }
    return list;
  }

  /// Club discovery keeps joined clubs visible and uses the same default as
  /// the club search filter: highest member count first.
  List<Club> get _clubsByMembers =>
      [..._visibleClubs]..sort(_compareClubsByMembers);

  /// Top clubs by membership — the "Trending Clubs" strip.
  List<Club> get _trendingClubs {
    return _clubsByMembers.take(3).toList();
  }

  /// The next highest-member clubs after the trending strip.
  List<Club> get _suggestedClubs {
    return _clubsByMembers.skip(3).take(3).toList();
  }

  // ─── People data ─────────────────────────────────────────────────────────

  List<User> get _peopleDirectory {
    final byId = <String, User>{
      for (final person in peopleService.cachedPeople) person.id: person,
      for (final person in _people) person.id: person,
    };
    return byId.values.toList();
  }

  List<String> get _majorFilterOptions {
    final options = <String>[...kAcademicPrograms];
    final normalized = options.map(normalizeAcademicProgramName).toSet();
    final additional = <String>[];
    for (final person in _peopleDirectory) {
      final major = userState.majors[person.id]?.trim() ?? '';
      if (major.isNotEmpty &&
          normalized.add(normalizeAcademicProgramName(major))) {
        additional.add(major);
      }
    }
    additional.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [...options, ...additional];
  }

  int _personSearchScore(User person, String query) {
    final name = userState.displayNameFor(person.id, person.name).toLowerCase();
    final words = name.split(RegExp(r'\s+'));
    if (name == query) return 0;
    if (words.any((word) => word == query)) return 1;
    if (name.startsWith(query)) return 2;
    if (words.any((word) => word.startsWith(query))) return 3;
    return 4;
  }

  /// Search by first name, surname, or display name, with strongest matches
  /// first, intersected with the major and year filters.
  List<User> get _resultPeople {
    final q = _query.toLowerCase().trim();
    final majors = _filters.majors.map(normalizeAcademicProgramName).toSet();
    final years = _filters.years;

    final matches = _peopleDirectory.where((person) {
      if (person.id == _myId || moderationService.isUserBlocked(person.id)) {
        return false;
      }
      // The guest joyride seeds a fabricated campus so its demo screens have
      // activity. Those accounts must never be discoverable in the student
      // directory.
      if (person.id.startsWith(kGuestIdPrefix)) return false;
      final major = normalizeAcademicProgramName(
        userState.majors[person.id] ?? '',
      );
      if (majors.isNotEmpty && !majors.contains(major)) return false;
      final year = userState.years[person.id]?.trim() ?? '';
      if (years.isNotEmpty && !years.contains(year)) return false;
      if (q.isEmpty) return true;
      final name = userState
          .displayNameFor(person.id, person.name)
          .toLowerCase();
      return name.contains(q) || person.email.toLowerCase().contains(q);
    }).toList();

    matches.sort((a, b) {
      if (q.isNotEmpty) {
        final byRelevance = _personSearchScore(
          a,
          q,
        ).compareTo(_personSearchScore(b, q));
        if (byRelevance != 0) return byRelevance;
      }
      final aName = userState.displayNameFor(a.id, a.name);
      final bName = userState.displayNameFor(b.id, b.name);
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });
    return matches;
  }

  /// The "Suggested Profiles" rows shown before the student searches. Like
  /// the club strips, this only offers people they do not already follow —
  /// and never themselves. Search results stay unfiltered so you can still
  /// look up someone you follow by name.
  List<User> get _suggestedProfiles {
    final preview = peopleService.randomProfiles(excludeId: _myId);
    final source = preview.isNotEmpty
        ? preview
        : _peopleDirectory.where((person) => person.id != _myId).toList();
    final candidates = source
        .where(
          (person) =>
              person.id != _myId &&
              !userState.isFollowingUser(person.id) &&
              !moderationService.isUserBlocked(person.id),
        )
        .toList();
    final candidatesById = {
      for (final candidate in candidates) candidate.id: candidate,
    };
    final desiredCount = candidates.length.clamp(0, 3);

    if (_suggestedProfileIds.length > desiredCount) {
      _suggestedProfileIds.removeRange(
        desiredCount,
        _suggestedProfileIds.length,
      );
    }

    final assigned = <String>{};
    final needsReplacement = <bool>[];
    for (final id in _suggestedProfileIds) {
      needsReplacement.add(
        !candidatesById.containsKey(id) || !assigned.add(id),
      );
    }

    User? takeNextCandidate() {
      for (final candidate in candidates) {
        if (assigned.add(candidate.id)) return candidate;
      }
      return null;
    }

    // Replace an invalid recommendation in its existing slot. This keeps the
    // untouched rows stationary instead of shifting every following profile
    // upward when one person is followed.
    for (var i = 0; i < _suggestedProfileIds.length; i++) {
      if (!needsReplacement[i]) continue;

      final replacement = takeNextCandidate();
      if (replacement == null) {
        _suggestedProfileIds.removeAt(i);
        needsReplacement.removeAt(i);
        i--;
      } else {
        _suggestedProfileIds[i] = replacement.id;
      }
    }

    while (_suggestedProfileIds.length < desiredCount) {
      final next = takeNextCandidate();
      if (next == null) break;
      _suggestedProfileIds.add(next.id);
    }

    return [for (final id in _suggestedProfileIds) ?candidatesById[id]];
  }

  void _persist() => userPrefsService.save(_myId);

  Future<void> _loadPeople() async {
    if (_peopleLoading) return;
    setState(() {
      _peopleLoading = true;
      _peopleHasError = false;
    });

    try {
      await peopleService.hydrateFollowing(_myId);
      final people = await peopleService.fetchPeople(excludeId: _myId);
      if (!mounted) return;
      setState(() {
        _people = people;
        _peopleLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _people = users.where((user) => user.id != _myId).toList();
        _peopleLoading = false;
        _peopleHasError = true;
      });
    }
  }

  Future<void> _togglePersonFollow(User person) async {
    if (!_canFollowPeople) return;

    final nowFollowing = !userState.isFollowingUser(person.id);
    final feedbackVersion = ++_peopleFeedbackVersion;

    userState.toggleFollowUser(person.id);
    _persist();

    setState(() {
      _peopleFeedbackIsFollowing = nowFollowing;
      _peopleFeedback = nowFollowing
          ? AppLocalizations.of(context)!.nowFollowingPerson(person.name)
          : AppLocalizations.of(context)!.unfollowedPerson(person.name);
    });

    try {
      await peopleService.setFollowing(
        followerId: _myId,
        followingId: person.id,
        follow: nowFollowing,
      );
      _persist();
    } catch (_) {
      userState.toggleFollowUser(person.id);
      _persist();
      if (!mounted) return;
      setState(() {
        _peopleFeedbackIsFollowing = !nowFollowing;
        _peopleFeedback = AppLocalizations.of(context)!.couldNotUpdateFollow;
      });
      return;
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || feedbackVersion != _peopleFeedbackVersion) return;
      setState(() => _peopleFeedback = null);
    });
  }

  // ─── Filters ─────────────────────────────────────────────────────────────

  /// Every category [ExploreScreen.categoryFor] can return, in the order the
  /// design lists them, limited to the ones actually present on a club.
  List<String> get _categoryOptions {
    final present = <String>{
      for (final club in _visibleClubs)
        ExploreScreen.categoryFor(context, club),
    };
    final l10n = AppLocalizations.of(context)!;
    final ordered = [
      l10n.categoryEngineering,
      l10n.categoryBusiness,
      l10n.categoryArts,
      l10n.categorySports,
      l10n.categorySocial,
      l10n.categoryAcademic,
    ];
    return ordered.where(present.contains).toList();
  }

  Future<void> _openFilters() async {
    final result = await showSearchFilterSheet(
      context: context,
      filters: _filters,
      categories: _categoryOptions,
      majors: _majorFilterOptions,
      years: fallbackAcademicYearNames,
      yearLabelOf: academicYearDisplayName,
    );
    if (result == null || !mounted) return;

    if (result.resetToDiscovery) {
      FocusManager.instance.primaryFocus?.unfocus();
      _searchController.clear();
      setState(() {
        _filters = result.filters;
        _directoryScopeApplied = false;
        _query = '';
        _peopleFeedback = null;
        _peopleFeedbackVersion++;
      });
      return;
    }

    setState(() {
      _filters = result.filters;
      _directoryScopeApplied = true;
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SearchColors.background,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([userState, moderationService]),
          builder: (context, _) => Column(
            children: [
              _searchBar(),
              _followFeedback(),
              Expanded(
                child: _showingResults ? _resultsList() : _discoveryList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  EdgeInsets get _listPadding => EdgeInsets.fromLTRB(
    20,
    0,
    20,
    // Clear the floating bottom navigation bar.
    MediaQuery.paddingOf(context).bottom + 112,
  );

  // ─── Search bar ──────────────────────────────────────────────────────────

  Widget _searchBar() {
    final l10n = AppLocalizations.of(context)!;
    final activeCount = _filters.activeCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        key: onboardingAnchors.keyFor(OnboardingAnchors.searchField),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: SearchColors.field,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: SearchColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                style: figtree(
                  size: 14,
                  weight: FontWeight.w400,
                  color: SearchColors.text,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: l10n.searchEverythingHint,
                  hintStyle: figtree(
                    size: 14,
                    weight: FontWeight.w400,
                    color: SearchColors.muted,
                  ),
                ),
              ),
            ),
            if (_query.isNotEmpty) ...[
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: l10n.clearSearchTooltip,
                child: GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: SearchColors.muted,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: l10n.filtersTitle,
              child: GestureDetector(
                key: const ValueKey('search-filter-button'),
                onTap: _openFilters,
                child: Badge(
                  isLabelVisible: activeCount > 0,
                  backgroundColor: SearchColors.accent,
                  label: Text(
                    '$activeCount',
                    style: figtree(
                      size: 9,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  child: Icon(
                    Icons.tune,
                    size: 20,
                    color: activeCount > 0
                        ? SearchColors.accentText
                        : SearchColors.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Transient confirmation after a follow / unfollow. Not part of the
  /// handoff, but removing it would drop the only feedback the student gets
  /// when the network call fails.
  Widget _followFeedback() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: AlignmentDirectional.topStart,
            child: child,
          ),
        ),
        child: _peopleFeedback == null
            ? const SizedBox(
                key: ValueKey('no-follow-feedback'),
                width: double.infinity,
              )
            : Container(
                key: ValueKey(_peopleFeedback),
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _peopleFeedbackIsFollowing
                      ? SearchColors.accentSurface
                      : SearchColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _peopleFeedbackIsFollowing
                        ? SearchColors.accent
                        : SearchColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _peopleFeedbackIsFollowing
                          ? Icons.check_circle_rounded
                          : Icons.person_remove_rounded,
                      size: 18,
                      color: _peopleFeedbackIsFollowing
                          ? SearchColors.accentText
                          : SearchColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _peopleFeedback!,
                        style: figtree(
                          size: 12,
                          weight: FontWeight.w600,
                          color: SearchColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ─── Discovery ───────────────────────────────────────────────────────────

  Widget _discoveryList() {
    final l10n = AppLocalizations.of(context)!;
    final trending = _trendingClubs;
    final suggestedClubs = _suggestedClubs;
    final suggestedProfiles = _suggestedProfiles;

    return ListView(
      key: const ValueKey('search-discovery-list'),
      padding: _listPadding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (trending.isNotEmpty) ...[
          _sectionTitle(
            l10n.trendingClubs,
            icon: Icons.local_fire_department_rounded,
            size: 16,
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < trending.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _trendingCard(trending[i])),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (suggestedClubs.isNotEmpty) ...[
          _sectionTitle(l10n.suggestedClubs, size: 16),
          const SizedBox(height: 12),
          for (var i = 0; i < suggestedClubs.length; i++) ...[
            _recommendationSwap(
              slotKey: 'suggested-club-slot-$i',
              itemKey: 'suggested-club-${suggestedClubs[i].id}',
              child: _clubRow(suggestedClubs[i]),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
        ],
        if (suggestedProfiles.isNotEmpty) ...[
          // The Figma layer is named `person` but draws a bell glyph, which is
          // what the frame renders — matched here to the render, not the name.
          _sectionTitle(
            l10n.suggestedProfiles,
            icon: Icons.notifications_none_rounded,
            size: 15,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < suggestedProfiles.length; i++) ...[
            _recommendationSwap(
              slotKey: 'suggested-profile-slot-$i',
              itemKey: 'suggested-profile-${suggestedProfiles[i].id}',
              child: _personRow(suggestedProfiles[i]),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (trending.isEmpty &&
            suggestedClubs.isEmpty &&
            suggestedProfiles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 80),
            // Nothing left to recommend reads two ways: there is genuinely
            // no directory yet, or the student has already joined and
            // followed everything in it. Only the second deserves a
            // congratulatory note.
            child: _visibleClubs.isEmpty && _peopleDirectory.isEmpty
                ? _emptyState(l10n.noClubsFound, l10n.exploreClubsHint)
                : _emptyState(l10n.noNewClubsToSuggest, l10n.tryNameSearch),
          ),
      ],
    );
  }

  // ─── Results ─────────────────────────────────────────────────────────────

  Widget _resultsList() {
    if (_searchingAllDirectories) return _combinedResults();
    return _searchingClubs ? _clubResults() : _peopleResults();
  }

  Widget _combinedResults() {
    final l10n = AppLocalizations.of(context)!;
    final clubResults = _resultClubs;
    final peopleResults = _resultPeople;
    final skeletonCount = _peopleLoading && peopleResults.isEmpty ? 5 : 0;

    if (clubResults.isEmpty && peopleResults.isEmpty && skeletonCount == 0) {
      return _emptyState(l10n.noContentMatch, l10n.tryDifferentSearch);
    }

    final clubItemCount = clubResults.isEmpty ? 0 : clubResults.length + 1;
    final peopleItemCount = peopleResults.isNotEmpty
        ? peopleResults.length + 1
        : skeletonCount == 0
        ? 0
        : skeletonCount + 1;

    return ListView.builder(
      key: const ValueKey('combined-search-results'),
      padding: _listPadding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: clubItemCount + peopleItemCount,
      itemBuilder: (context, index) {
        var sectionIndex = index;

        if (clubResults.isNotEmpty) {
          if (sectionIndex == 0) {
            return _resultsLabel(
              '${l10n.clubs} · ${l10n.clubsCountLabel(clubResults.length)}',
            );
          }
          sectionIndex--;
          if (sectionIndex < clubResults.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _clubRow(clubResults[sectionIndex]),
            );
          }
          sectionIndex -= clubResults.length;
        }

        if (sectionIndex == 0) {
          final countLabel = peopleResults.isEmpty
              ? l10n.students
              : '${l10n.students} · '
                    '${l10n.resultsCountLabel(peopleResults.length)}';
          return Padding(
            padding: EdgeInsets.only(top: clubResults.isEmpty ? 0 : 6),
            child: _resultsLabel(countLabel),
          );
        }
        sectionIndex--;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: peopleResults.isEmpty
              ? const _PersonRowSkeleton()
              : _personRow(peopleResults[sectionIndex]),
        );
      },
    );
  }

  Widget _clubResults() {
    final l10n = AppLocalizations.of(context)!;
    final results = _resultClubs;

    if (results.isEmpty) {
      return _emptyState(l10n.noClubsMatch, l10n.tryDifferentSearch);
    }

    return ListView.builder(
      padding: _listPadding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _resultsLabel(l10n.clubsCountLabel(results.length));
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _clubRow(results[i - 1]),
        );
      },
    );
  }

  Widget _peopleResults() {
    final l10n = AppLocalizations.of(context)!;
    final results = _resultPeople;
    final filteringByMajor = _filters.majors.isNotEmpty;

    if (_peopleLoading && results.isEmpty) {
      return ListView.builder(
        padding: _listPadding,
        itemCount: 7,
        itemBuilder: (context, _) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: _PersonRowSkeleton(),
        ),
      );
    }

    if (results.isEmpty) {
      return _emptyState(
        filteringByMajor ? S.noPeopleInSelectedMajor : l10n.noOneMatches,
        filteringByMajor
            ? S.tryAnotherMajorOrName
            : _query.trim().isNotEmpty
            ? l10n.tryNameSearch
            : l10n.profilesWillAppear,
        note: _peopleHasError ? l10n.couldNotLoadPeople : null,
      );
    }

    return ListView.builder(
      padding: _listPadding,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _resultsLabel(
            [
              if (filteringByMajor) _filters.majors.join(', '),
              l10n.resultsCountLabel(results.length),
            ].join(' · '),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _personRow(results[i - 1]),
        );
      },
    );
  }

  // ─── Shared atoms ────────────────────────────────────────────────────────

  Widget _sectionTitle(String text, {IconData? icon, required double size}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: SearchColors.accentText),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            style: figtree(
              size: size,
              weight: size >= 16 ? FontWeight.w800 : FontWeight.w700,
              color: SearchColors.text,
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultsLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: figtree(
          size: 11,
          weight: FontWeight.w700,
          color: SearchColors.muted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  /// Keeps each discovery slot in place while its recommendation changes, so
  /// a replacement can softly move in instead of snapping into the row.
  Widget _recommendationSwap({
    required String slotKey,
    required String itemKey,
    required Widget child,
  }) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final itemValueKey = ValueKey(itemKey);
    final switchDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 420);
    final exitDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260);

    return AnimatedSize(
      duration: switchDuration,
      reverseDuration: exitDuration,
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topStart,
      child: AnimatedSwitcher(
        key: ValueKey(slotKey),
        duration: switchDuration,
        reverseDuration: exitDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: AlignmentDirectional.centerStart,
          clipBehavior: Clip.none,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (transitionChild, animation) {
          final isIncoming = transitionChild.key == itemValueKey;
          final offset = Tween<Offset>(
            begin: isIncoming
                ? const Offset(0.035, 0)
                : const Offset(-0.022, 0),
            end: Offset.zero,
          ).animate(animation);
          final scale = Tween<double>(
            begin: isIncoming ? 0.985 : 0.992,
            end: 1,
          ).animate(animation);

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offset,
              child: ScaleTransition(
                scale: scale,
                alignment: Alignment.centerLeft,
                child: transitionChild,
              ),
            ),
          );
        },
        child: KeyedSubtree(key: itemValueKey, child: child),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle, {String? note}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: figtree(
                size: 15,
                weight: FontWeight.w700,
                color: SearchColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: figtree(
                size: 13,
                weight: FontWeight.w400,
                color: SearchColors.muted,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(
                note,
                textAlign: TextAlign.center,
                style: figtree(
                  size: 11,
                  weight: FontWeight.w400,
                  color: SearchColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The `Join` / `Follow` pill. Filled accent when the action is available,
  /// outlined accent once it has been taken.
  Widget _actionPill({
    required bool active,
    required String activeLabel,
    required String inactiveLabel,
    required VoidCallback onTap,
  }) {
    return _SearchActionPill(
      active: active,
      activeLabel: activeLabel,
      inactiveLabel: inactiveLabel,
      onTap: onTap,
    );
  }

  Widget _metaDot() {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SearchColors.muted,
      ),
    );
  }

  // ─── Cards and rows ──────────────────────────────────────────────────────

  Widget _trendingCard(Club club) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => _openClub(club),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SearchColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SearchColors.border),
          boxShadow: SearchColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClubAvatar(
              clubId: club.id,
              clubName: club.name,
              color: _hueFor(clubOrdinal(club.id)),
              imageUrl: club.logoUrl,
              size: 40,
              fontSize: 16,
              borderRadius: 12,
            ),
            const SizedBox(height: 8),
            Text(
              club.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figtree(
                size: 13,
                weight: FontWeight.w700,
                color: SearchColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.membersCount(clubMemberCount(club.id)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figtree(
                size: 11,
                weight: FontWeight.w400,
                color: SearchColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clubRow(Club club) {
    final l10n = AppLocalizations.of(context)!;
    final category = ExploreScreen.categoryFor(context, club);
    final joined = userState.isFollowing(club.id);

    return GestureDetector(
      onTap: () => _openClub(club),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SearchColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SearchColors.border),
        ),
        child: Row(
          children: [
            ClubAvatar(
              clubId: club.id,
              clubName: club.name,
              color: _hueFor(clubOrdinal(club.id)),
              imageUrl: club.logoUrl,
              size: 44,
              fontSize: 17,
              shape: 'circle',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    club.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: figtree(
                      size: 14,
                      weight: FontWeight.w700,
                      color: SearchColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: figtree(
                            size: 11,
                            weight: FontWeight.w500,
                            color: SearchColors.accentText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _metaDot(),
                      const SizedBox(width: 6),
                      Text(
                        l10n.membersCount(clubMemberCount(club.id)),
                        style: figtree(
                          size: 11,
                          weight: FontWeight.w400,
                          color: SearchColors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _actionPill(
              active: joined,
              activeLabel: l10n.joined,
              inactiveLabel: l10n.join,
              onTap: () => handleFollowTap(context, club.id, () {
                _persist();
                setState(() {});
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _personRow(User person) {
    return _PersonRow(
      key: ValueKey(person.id),
      user: person,
      handle: _handleFor(person),
      subtitle: _personSubtitle(person),
      // Hue from the id, not a list index: stable as the directory reorders,
      // and O(1) per row rather than a directory scan.
      color: _hueFor(person.id.hashCode),
      canFollow: _canFollowPeople,
      following: userState.isFollowingUser(person.id),
      onFollow: () => _togglePersonFollow(person),
      onOpen: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserProfileScreen(user: person)),
      ),
    );
  }

  void _openClub(Club club) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ClubProfileScreen(club: club, color: _hueFor(clubOrdinal(club.id))),
      ),
    );
  }

  /// The `@handle` line in the design. Students have no handle field, so the
  /// local part of the KU address stands in for one.
  String _handleFor(User user) {
    final local = user.email.split('@').first.trim();
    return local.isEmpty ? '' : '@$local';
  }

  String _personSubtitle(User u) {
    final major = userState.majors[u.id]?.trim();
    final year = userState.years[u.id]?.trim();
    if (major != null && major.isNotEmpty) {
      return year != null && year.isNotEmpty
          ? '$major · ${academicYearDisplayName(year)}'
          : major;
    }
    return u.email.isNotEmpty
        ? u.email
        : AppLocalizations.of(context)!.studentProfile;
  }
}

// ─── Person row ──────────────────────────────────────────────────────────────

class _SearchActionPill extends StatelessWidget {
  const _SearchActionPill({
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
    required this.onTap,
  });

  final bool active;
  final String activeLabel;
  final String inactiveLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final surfaceDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final labelDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 190);

    return AppPressable(
      onTap: onTap,
      pressedScale: 0.95,
      child: AnimatedSize(
        duration: surfaceDuration,
        curve: Curves.easeOutCubic,
        alignment: AlignmentDirectional.centerEnd,
        child: AnimatedContainer(
          duration: surfaceDuration,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.transparent : SearchColors.accent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? SearchColors.accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: AnimatedSwitcher(
            duration: labelDuration,
            reverseDuration: labelDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              active ? activeLabel : inactiveLabel,
              key: ValueKey(active),
              style: figtree(
                size: 12,
                weight: FontWeight.w700,
                color: active ? SearchColors.accentText : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRowSkeleton extends StatelessWidget {
  const _PersonRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SearchColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SearchColors.border),
      ),
      child: Row(
        children: [
          const SkeletonBox.circle(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(
                  width: 130,
                  height: 13,
                  borderRadius: BorderRadius.all(Radius.circular(7)),
                ),
                const SizedBox(height: 7),
                SkeletonBox(
                  width: 84,
                  height: 10,
                  borderRadius: BorderRadius.all(Radius.circular(5)),
                ),
                const SizedBox(height: 7),
                SkeletonBox(
                  width: double.infinity,
                  height: 10,
                  borderRadius: BorderRadius.all(Radius.circular(5)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SkeletonBox(
            width: 68,
            height: 28,
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatefulWidget {
  final User user;
  final String handle;
  final String subtitle;
  final Color color;
  final bool canFollow;
  final bool following;
  final VoidCallback onFollow;
  final VoidCallback onOpen;

  const _PersonRow({
    super.key,
    required this.user,
    required this.handle,
    required this.subtitle,
    required this.color,
    required this.canFollow,
    required this.following,
    required this.onFollow,
    required this.onOpen,
  });

  @override
  State<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<_PersonRow> {
  late bool _displayFollowing;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    _displayFollowing = widget.following;
  }

  @override
  void didUpdateWidget(covariant _PersonRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_changing && oldWidget.following != widget.following) {
      _displayFollowing = widget.following;
    }
  }

  Future<void> _toggleFollow() async {
    if (_changing || !widget.canFollow) return;
    setState(() {
      _changing = true;
      _displayFollowing = !_displayFollowing;
    });
    widget.onFollow();

    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (mounted) setState(() => _changing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: widget.onOpen,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SearchColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _changing && _displayFollowing
                ? SearchColors.accent
                : SearchColors.border,
          ),
        ),
        child: Row(
          children: [
            UserAvatar(
              userId: widget.user.id,
              name: widget.user.name,
              size: 44,
              fontSize: 16,
              backgroundColor: widget.color.withValues(alpha: 0.14),
              textColor: widget.color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userState.displayNameFor(widget.user.id, widget.user.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: figtree(
                      size: 14,
                      weight: FontWeight.w700,
                      color: SearchColors.text,
                    ),
                  ),
                  if (widget.handle.isNotEmpty)
                    Text(
                      widget.handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: figtree(
                        size: 11,
                        weight: FontWeight.w400,
                        color: SearchColors.muted,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: figtree(
                      size: 11,
                      weight: FontWeight.w400,
                      color: SearchColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.canFollow) ...[
              const SizedBox(width: 10),
              _SearchActionPill(
                active: _displayFollowing,
                activeLabel: l10n.following,
                inactiveLabel: l10n.follow,
                onTap: _toggleFollow,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';

import '../models/feed_v2.dart';
import 'feed_v2_service.dart';
import 'guest_session.dart';

/// Paging state for the versioned feed path.
///
/// The controller owns only typed server state. Adapting it to the legacy UI
/// models is intentionally kept in FeedScreen so released-client models and
/// services remain untouched.
class FeedV2Controller extends ChangeNotifier {
  FeedV2Controller({required FeedPageV2Source source, this.pageSize = 25})
    : _source = source;

  final FeedPageV2Source _source;
  final int pageSize;

  List<FeedPostV2> _items = const [];
  List<FeedEventV2> _upcomingEvents = const [];
  List<FeedPersonV2> _suggestedPeople = const [];
  List<FeedClubV2> _suggestedClubs = const [];
  FeedCursorV2? _nextCursor;
  bool _hasMore = true;
  bool _followedOnly = false;
  bool _isInitialLoading = false;
  bool _isRefreshing = false;
  bool _isNextPageLoading = false;
  bool _hasLoadedFirstPage = false;
  Object? _initialError;
  Object? _pageError;
  Future<void>? _firstPageTask;
  Future<void>? _nextPageTask;
  int _generation = 0;
  int _dataRevision = 0;
  int _firstPageRevision = 0;

  List<FeedPostV2> get items => _items;
  List<FeedEventV2> get upcomingEvents => _upcomingEvents;
  List<FeedPersonV2> get suggestedPeople => _suggestedPeople;
  List<FeedClubV2> get suggestedClubs => _suggestedClubs;
  bool get hasMore => _hasMore;
  bool get followedOnly => _followedOnly;
  bool get isInitialLoading => _isInitialLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isNextPageLoading => _isNextPageLoading;
  bool get hasLoadedFirstPage => _hasLoadedFirstPage;
  Object? get initialError => _initialError;
  Object? get pageError => _pageError;
  bool get isEmpty => _items.isEmpty;
  int get dataRevision => _dataRevision;
  int get firstPageRevision => _firstPageRevision;

  Future<void> loadFirstPage({bool followedOnly = false, bool force = false}) {
    // Guest mode leaves `hasLoadedFirstPage` false on purpose. FeedScreen then
    // renders every rail from the in-memory registries — `newsPosts`, `events`,
    // `clubs`, `peopleService.cachedPeople` — through the pre-v2 fallback it
    // still keeps for exactly this case, which is where the seed world lives.
    if (guestSession.isActive) {
      _followedOnly = followedOnly;
      return Future.value();
    }
    final inFlight = _firstPageTask;
    if (inFlight != null && _followedOnly == followedOnly) return inFlight;

    if (force) {
      // A pull-to-refresh defines a new cursor chain. Let any old next-page
      // response finish, but make its generation stale so it cannot append to
      // the refreshed first page.
      _generation++;
      _nextPageTask = null;
      _isNextPageLoading = false;
    }
    if (_followedOnly != followedOnly) {
      _generation++;
      _items = const [];
      _upcomingEvents = const [];
      _suggestedPeople = const [];
      _suggestedClubs = const [];
      _nextCursor = null;
      _hasMore = true;
      _hasLoadedFirstPage = false;
      _pageError = null;
    }
    _followedOnly = followedOnly;
    final generation = _generation;

    late final Future<void> task;
    task =
        _loadFirstPage(
          generation: generation,
          force: force,
          refreshing: force && _items.isNotEmpty,
        ).whenComplete(() {
          if (identical(_firstPageTask, task)) _firstPageTask = null;
        });
    _firstPageTask = task;
    return task;
  }

  Future<void> refresh() =>
      loadFirstPage(followedOnly: _followedOnly, force: true);

  Future<void> _loadFirstPage({
    required int generation,
    required bool force,
    required bool refreshing,
  }) async {
    _isRefreshing = refreshing;
    _isInitialLoading = !refreshing;
    _initialError = null;
    _pageError = null;
    notifyListeners();

    try {
      final page = await _source.fetchPage(
        limit: pageSize,
        followedOnly: _followedOnly,
        force: force,
      );
      if (generation != _generation) return;
      _applyFirstPage(page);
    } catch (error) {
      if (generation != _generation) return;
      _initialError = error;
    } finally {
      if (generation == _generation) {
        _isInitialLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadNextPage() {
    if (guestSession.isActive) return Future.value();
    final inFlight = _nextPageTask;
    if (inFlight != null) return inFlight;
    if (_isInitialLoading ||
        _isRefreshing ||
        !_hasMore ||
        _nextCursor == null) {
      return Future.value();
    }

    final generation = _generation;
    late final Future<void> task;
    task = _loadNextPage(generation).whenComplete(() {
      if (identical(_nextPageTask, task)) _nextPageTask = null;
    });
    _nextPageTask = task;
    return task;
  }

  Future<void> _loadNextPage(int generation) async {
    final cursor = _nextCursor;
    if (cursor == null) return;
    _isNextPageLoading = true;
    _pageError = null;
    notifyListeners();

    try {
      final page = await _source.fetchPage(
        cursor: cursor,
        limit: pageSize,
        followedOnly: _followedOnly,
        force: true,
      );
      if (generation != _generation) return;

      final byId = <String, FeedPostV2>{
        for (final item in _items) item.id: item,
      };
      for (final item in page.items) {
        byId.putIfAbsent(item.id, () => item);
      }
      _items = byId.values.toList()
        ..sort((a, b) {
          final byTime = b.createdAt.compareTo(a.createdAt);
          return byTime != 0 ? byTime : b.id.compareTo(a.id);
        });
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore && page.nextCursor != null;
      _dataRevision++;
    } catch (error) {
      if (generation == _generation) _pageError = error;
    } finally {
      if (generation == _generation) {
        _isNextPageLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> retry() {
    if (_items.isEmpty) {
      return loadFirstPage(followedOnly: _followedOnly, force: true);
    }
    return loadNextPage();
  }

  /// Removes content already confirmed deleted by the existing mutation path.
  /// The remaining keyset cursor is still valid because cursor comparison does
  /// not require the boundary row to continue existing.
  void removeItems(Iterable<String> ids) {
    final removedIds = ids.toSet();
    if (removedIds.isEmpty) return;
    final next = _items.where((item) => !removedIds.contains(item.id)).toList();
    if (next.length == _items.length) return;
    _items = next;
    _dataRevision++;
    notifyListeners();
  }

  void reset({required bool followedOnly}) {
    _generation++;
    _followedOnly = followedOnly;
    _items = const [];
    _upcomingEvents = const [];
    _suggestedPeople = const [];
    _suggestedClubs = const [];
    _nextCursor = null;
    _hasMore = true;
    _isInitialLoading = false;
    _isRefreshing = false;
    _isNextPageLoading = false;
    _hasLoadedFirstPage = false;
    _initialError = null;
    _pageError = null;
    _firstPageTask = null;
    _nextPageTask = null;
    notifyListeners();
  }

  void _applyFirstPage(FeedPageV2 page) {
    final seen = <String>{};
    _items = [
      for (final item in page.items)
        if (seen.add(item.id)) item,
    ];
    _upcomingEvents = page.upcomingEvents;
    _suggestedPeople = page.suggestedPeople;
    _suggestedClubs = page.suggestedClubs;
    _nextCursor = page.nextCursor;
    _hasMore = page.hasMore && page.nextCursor != null;
    _hasLoadedFirstPage = true;
    _firstPageRevision++;
    _dataRevision++;
  }
}

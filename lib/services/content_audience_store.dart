import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/content_audience.dart';
import 'guest_session.dart';

/// Where a post's or event's audience actually lives, keyed by content id.
///
/// This is a *side* store rather than a field on the models, and that is
/// deliberate. `SupabaseContentService.refreshPublicContent` rebuilds the global
/// `newsPosts` and `events` lists from scratch on every refresh
/// (`..clear()..addAll(...)`), and the Feed v2 adapter rebuilds each `NewsPost`
/// from its DTO — neither can carry a column the database does not have yet. A
/// field on the model would therefore be silently erased a second after it was
/// written. Keyed by id in a box of its own, the choice survives every one of
/// those rebuilds untouched, so no re-hydration hook is needed anywhere.
///
/// Once the `audience` column ships, the resolver in `content_visibility.dart`
/// flips to preferring the model field and this becomes a write-through mirror.
///
/// Keyed by content id and **not** namespaced by viewer, unlike
/// `ModerationService`: an audience is a property of the content its author
/// chose it for, not of whoever happens to be looking. Namespacing it per user
/// would lose it the moment the author switched accounts on the same device.
class ContentAudienceStore extends ChangeNotifier {
  static const _boxName = 'content_audience_v1';
  static const _key = 'audiences';

  /// contentId → audience, for genuinely restricted content only. A flat map
  /// across posts *and* events, because ids are unique across both (Supabase
  /// UUIDs, plus the `p_<millis>` / `ev_` / `guest_` local prefixes) and the
  /// resolver then needs no post-vs-event branch.
  final Map<String, ContentAudience> _byId = {};
  Box<dynamic>? _box;

  bool get isReady => _box != null;

  Future<void> initialize() async {
    if (_box != null) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    final raw = _box!.get(_key);
    if (raw is Map) {
      _byId.clear();
      for (final entry in raw.entries) {
        final id = entry.key.toString();
        if (id.isEmpty) continue;
        final audience = contentAudienceFromWire(entry.value);
        // A stored `everyone` is either corruption or a leftover from an older
        // build; either way it carries no information. Drop it.
        if (audience == ContentAudience.everyone) continue;
        _byId[id] = audience;
      }
      notifyListeners();
    }
  }

  /// The locally recorded audience, or `null` when this content has none.
  ///
  /// Nullable on purpose: "no record" has to stay distinguishable from
  /// "explicitly everyone", or the remote-authoritative version of this store
  /// cannot tell a stale local override from a deliberate one.
  ContentAudience? audienceFor(String contentId) => _byId[contentId];

  Future<void> setAudience(String contentId, ContentAudience audience) async {
    if (contentId.isEmpty) return;
    if (audience == ContentAudience.everyone) {
      // Public is the default everywhere, so store nothing rather than a row
      // saying "no restriction" — it keeps the map to restricted content only.
      if (_byId.remove(contentId) == null) return;
    } else {
      if (_byId[contentId] == audience) return;
      _byId[contentId] = audience;
    }
    await _persist();
  }

  /// Bulk-apply audiences without a write per entry — used by the guest world's
  /// seeding pass, and by the remote reconcile once the column exists.
  void seedAudiences(Map<String, ContentAudience> byId) {
    var changed = false;
    for (final entry in byId.entries) {
      if (entry.key.isEmpty) continue;
      if (entry.value == ContentAudience.everyone) {
        changed |= _byId.remove(entry.key) != null;
      } else if (_byId[entry.key] != entry.value) {
        _byId[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) unawaited(_persist());
  }

  /// A guest's demo audiences never reach Hive (see [_persist]) but this map
  /// outlives the session, so without this a joyride's restricted posts would
  /// still be filtered after a real account signs in on the same process.
  void clearSessionState() {
    if (_byId.isEmpty) return;
    _byId.clear();
    notifyListeners();
  }

  /// Drop entries whose content no longer exists. Nothing else prunes this map:
  /// `ContentStore` purges legacy fixture posts and events, and locally authored
  /// ids accumulate one per post, so without this it only ever grows.
  void pruneMissing(Iterable<String> liveContentIds) {
    if (_byId.isEmpty) return;
    final live = liveContentIds.toSet();
    final stale = _byId.keys.where((id) => !live.contains(id)).toList();
    if (stale.isEmpty) return;
    _byId.removeWhere((id, _) => stale.contains(id));
    unawaited(_persist());
  }

  Future<void> _persist() async {
    notifyListeners();
    if (guestSession.isActive) return;
    final box = _box;
    if (box == null) return;
    await box.put(_key, {
      for (final entry in _byId.entries) entry.key: entry.value.wireValue,
    });
  }
}

final contentAudienceStore = ContentAudienceStore();

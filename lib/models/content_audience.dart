/// Who a club post or event is addressed to.
///
/// Three **nested** tiers, not three disjoint groups: each is strictly narrower
/// than the one above it. Board members follow their own club, so [board] is a
/// subset of [followers], which is a subset of [everyone]. The values are
/// declared in widening-restriction order.
///
/// [everyone] is the default at four independent layers — the model constructors,
/// [contentAudienceFromWire], the resolver in `content_visibility.dart`, and (once
/// the column lands) the database default. Content authored before this feature
/// existed therefore reads as public without a backfill.
enum ContentAudience { everyone, followers, board }

extension ContentAudienceWire on ContentAudience {
  /// The persisted spelling: `everyone` | `followers` | `board`.
  ///
  /// Deliberately *not* the `club_followers` / `club_board` spelling that
  /// `notification_outbox_v2.audience_type` uses. There the club is not implied,
  /// because the same column also carries `group_members` and `direct_user`;
  /// here `club_id` sits on the same row and the prefix is noise.
  String get wireValue => name;
}

/// Tolerant decode. Anything unrecognised — including `null`, an unknown tier
/// written by a newer build, and rows persisted before this feature existed —
/// reads as [ContentAudience.everyone] so content is never accidentally hidden.
ContentAudience contentAudienceFromWire(Object? raw) {
  final name = raw?.toString() ?? '';
  for (final audience in ContentAudience.values) {
    if (audience.wireValue == name) return audience;
  }
  return ContentAudience.everyone;
}

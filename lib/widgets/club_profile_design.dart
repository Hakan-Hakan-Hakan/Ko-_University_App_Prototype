import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/theme_service.dart';
import '../theme/specialized_semantic_palettes.dart';
import 'clubup_design.dart';

export 'clubup_design.dart' show figtree;

/// The CLUB PROFİLE area of the ClubUp-Desings handoff — section label
/// `555:33`. The frames are the club's own view of itself:
///
/// * `club-profile` `337:8` / `337:98` — identity card, stat cells and the
///   Posts / Events / Board segmented tabs.
/// * `events` `343:12` / `343:109` and `board` `332:1963` / `332:2076` — the
///   other two tabs of the same screen.
/// * `board-members-all` `346:6` / `346:99` — the searchable full-page list
///   behind the Board tab's "View all".
/// * `insights` `347:6` / `347:166` — Club Insights.
///
/// `settings` `350:6` and everything it opens are deliberately *not* built
/// here: the club side of `SettingsScreen` is still the legacy screen.

// ── tokens ───────────────────────────────────────────────────────────────────

/// Sampled straight out of the frame PNGs with PIL, which is the only reliable
/// way to read this handoff's ramps.
///
/// The dark page is `#0A0A0A` over `#121212` cards — a *fifth* dark ramp in
/// this file, distinct from `ClubUpColors` (`#121212`/`#1E1E1E`), the profile
/// zinc (`#09090B`/`#18181B`), `ChatsColors` (`#121212`/`#1A1A1A`) and the
/// landing screen's. It shares the profile section's `#27272A` hairline.
class ClubProfileColors {
  const ClubProfileColors._();

  static SpecializedSemanticPalette of(BuildContext context) =>
      SpecializedSemanticPalettes.clubProfiles(Theme.of(context));

  static bool get _dark => themeService.isDark;

  /// Page background — `#FAF9F6` / `#0A0A0A`.
  static Color get page =>
      _dark ? const Color(0xFF0A0A0A) : const Color(0xFFFAF9F6);

  /// Every card on these frames — identity, stat cell, post, event, member
  /// row, metric tile — `#FFFFFF` / `#121212`.
  static Color get card => _dark ? const Color(0xFF121212) : Colors.white;

  /// Card hairline and the rule under a section header — `#E4E4E7` /
  /// `#27272A`.
  static Color get border =>
      _dark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);

  /// Primary text — `#18181B` / `#FAFAFA`.
  static Color get text =>
      _dark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);

  /// Secondary text — `#71717A` / `#A1A1AA`.
  static Color get muted =>
      _dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);

  /// Solid accent fills — the selected tab pill and the event CTA. Unchanged
  /// in dark, exactly as the frames draw it.
  static const Color accent = Color(0xFF800020);

  /// Accent *text*: the category chips, "View all" and
  /// "Most Popular" all lift to `#FA526B` in dark — the same bright rose the
  /// EVENT CREATION section uses, not the `#E8A1A6` of CHATS and settings.
  static Color get accentText => _dark ? const Color(0xFFFA526B) : accent;

  /// The tint behind a chip or a metric tile's icon — `#F2E5E8` / `#2B191C`.
  static Color get accentSurface =>
      _dark ? const Color(0xFF2B191C) : const Color(0xFFF2E5E8);

  /// The filled inputs and the search-results dropdown on
  /// `board-members` `413:7` — `#F4F4F5` / `#1E1E1E`. Sits *inside* a [card],
  /// which is why it is a third step rather than the page colour.
  static Color get field =>
      _dark ? const Color(0xFF1E1E1E) : const Color(0xFFF4F4F5);

  /// Destructive: the remove control's icon and its tinted pill —
  /// `#DC2626` on `#FEF2F2` / `#220F0F`.
  static const Color danger = Color(0xFFDC2626);
  static Color get dangerSurface =>
      _dark ? const Color(0xFF220F0F) : const Color(0xFFFEF2F2);
}

/// `profile-scroll` gutters: 16pt sides, 370pt of content on a 402pt frame.
const double kClubProfileGutter = 16;

/// Vertical rhythm between the identity card, the stats row, the tabs and the
/// stream below them.
const double kClubProfileGap = 20;

// ── chrome ───────────────────────────────────────────────────────────────────

/// `chat-header` `332:2208` — a 60pt band with a back chevron, an ExtraBold
/// title and up to two 40pt circular action buttons.
///
/// The `board-members-all` and `insights` frames use the same bar 44pt tall
/// with no actions, which is [compact].
class ClubProfileHeaderBar extends StatelessWidget {
  const ClubProfileHeaderBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
    this.compact = false,
  });

  final String title;

  /// Omitted on the club's own Profile tab root, which has nowhere to pop to.
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 44 : 60,
      color: ClubProfileColors.page,
      padding: const EdgeInsets.symmetric(horizontal: kClubProfileGutter),
      child: Row(
        children: [
          if (onBack != null) ...[
            Semantics(
              button: true,
              label: MaterialLocalizations.of(context).backButtonTooltip,
              child: GestureDetector(
                key: const ValueKey('club-profile-back'),
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: SizedBox(
                  width: 24,
                  height: 40,
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 26,
                    color: ClubProfileColors.text,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figtree(
                size: 20,
                weight: FontWeight.w800,
                color: ClubProfileColors.text,
                letterSpacing: -0.3,
              ),
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }
}

/// `insights-button` / `settings-button` — a 40pt circle on the card colour
/// with the page's hairline around it.
class ClubProfileCircleButton extends StatelessWidget {
  const ClubProfileCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: ClubProfileColors.card,
            shape: BoxShape.circle,
            border: Border.all(color: ClubProfileColors.border),
          ),
          child: Icon(icon, size: 20, color: ClubProfileColors.text),
        ),
      ),
    );
  }
}

/// Every card on these frames: `#FFFFFF` / `#121212`, 1pt hairline, and the
/// radius the frame's corner sweep measures at.
class ClubProfileCard extends StatelessWidget {
  const ClubProfileCard({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = ClubProfileColors.of(context);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ClubProfileColors.border),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.onSurface),
        child: IconTheme.merge(
          data: IconThemeData(color: colors.onSurface),
          child: child,
        ),
      ),
    );
    if (onTap == null && onLongPress == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: card,
    );
  }
}

// ── identity ─────────────────────────────────────────────────────────────────

/// Instagram-style verification mark used exclusively by club profiles.
///
/// The white check is painted separately so it remains white in both themes,
/// rather than becoming a cut-out that inherits the surface behind the icon.
class ClubVerifiedBadge extends StatelessWidget {
  const ClubVerifiedBadge({super.key, this.size = 18, this.semanticLabel});

  static const Color verificationColor = Color(0xFF800020);

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label =
        semanticLabel ??
        AppLocalizations.of(context)?.officialClubLabel ??
        'Verified club';

    return Semantics(
      label: label,
      image: true,
      child: SizedBox.square(
        key: const ValueKey('club-verified-badge'),
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.verified_rounded, size: size, color: verificationColor),
            Icon(
              Icons.check_rounded,
              size: size * 0.58,
              color: Colors.white,
              weight: 800,
            ),
          ],
        ),
      ),
    );
  }
}

/// A club account name with its verification mark kept directly beside it.
class ClubVerifiedName extends StatelessWidget {
  const ClubVerifiedName({
    super.key,
    required this.name,
    required this.style,
    this.maxLines = 1,
    this.badgeSize = 18,
    this.semanticLabel,
  });

  final String name;
  final TextStyle style;
  final int maxLines;
  final double badgeSize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final verifiedLabel =
        semanticLabel ??
        AppLocalizations.of(context)?.officialClubLabel ??
        'Verified club';

    return Semantics(
      label: '$name, $verifiedLabel',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            const SizedBox(width: 5),
            ClubVerifiedBadge(size: badgeSize, semanticLabel: verifiedLabel),
          ],
        ),
      ),
    );
  }
}

/// `club-identity-card` `337:30` — 64pt avatar, name, plain `@handle`, the
/// description and the category chips.
class ClubProfileIdentityCard extends StatelessWidget {
  const ClubProfileIdentityCard({
    super.key,
    required this.avatar,
    required this.name,
    required this.handle,
    required this.description,
    required this.categories,
    this.actions,
  });

  /// The club's real avatar widget — this area never owns image resolution.
  final Widget avatar;
  final String name;
  final String handle;
  final String description;
  final List<String> categories;

  /// Viewer actions under the chips. Null on the club's own profile — the
  /// frame is an admin looking at their own club, so it draws none. A student
  /// browsing the club gets Follow + Club Chat here.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return ClubProfileCard(
      key: const ValueKey('club-profile-identity-card'),
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ClubProfileColors.accent, width: 2),
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(child: SizedBox.expand(child: avatar)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClubVerifiedName(
                      name: name,
                      badgeSize: 17,
                      maxLines: 2,
                      style: figtree(
                        size: 20,
                        weight: FontWeight.w800,
                        color: ClubProfileColors.text,
                        height: 1.15,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '@$handle',
                      key: const ValueKey('club-profile-handle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: figtree(
                        size: 14,
                        weight: FontWeight.w600,
                        color: themeService.isDark
                            ? Colors.white
                            : ClubProfileColors.text,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: figtree(
                size: 13,
                weight: FontWeight.w400,
                color: ClubProfileColors.muted,
                height: 1.45,
              ),
            ),
          ],
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in categories)
                  ClubProfileChip(label: category),
              ],
            ),
          ],
          if (actions != null) ...[const SizedBox(height: 12), actions!],
        ],
      ),
    );
  }
}

/// A viewer action under the identity card's chips — geometry borrowed from the
/// student profile's Follow/Message pair (46pt tall, radius 14, 15/w700) so the
/// two peer-view screens read the same, painted in [ClubProfileColors].
class ClubProfileActionButton extends StatelessWidget {
  const ClubProfileActionButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : ClubProfileColors.text;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? ClubProfileColors.accent : Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: filled ? null : Border.all(color: ClubProfileColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
            ],
            // "Takip Ediliyor" is half again as long as "Following", and the
            // pair splits the card in two, so the label has to give.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: figtree(
                  size: 15,
                  weight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `tag-badge` / `chip-music` — accent text on the accent tint, fully rounded.
class ClubProfileChip extends StatelessWidget {
  const ClubProfileChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ClubProfileColors.accentSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: figtree(
          size: 11,
          weight: FontWeight.w700,
          color: ClubProfileColors.accentText,
          height: 1.2,
        ),
      ),
    );
  }
}

/// `stats-row` `337:39` — three compact equal cells with 8pt between them.
class ClubProfileStatsRow extends StatelessWidget {
  const ClubProfileStatsRow({super.key, required this.cells});

  final List<ClubProfileStat> cells;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('club-profile-stats'),
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _cell(cells[i])),
        ],
      ],
    );
  }

  Widget _cell(ClubProfileStat stat) {
    return ClubProfileCard(
      radius: 12,
      onTap: stat.onTap,
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              stat.value,
              style: figtree(
                size: 19,
                weight: FontWeight.w800,
                color: ClubProfileColors.text,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              stat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figtree(
                size: 11.5,
                weight: FontWeight.w500,
                color: ClubProfileColors.muted,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClubProfileStat {
  const ClubProfileStat({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;
}

/// `segmented-tabs` `337:49` — a 38pt track with a 30pt accent pill.
class ClubProfileSegmentedTabs extends StatelessWidget {
  const ClubProfileSegmentedTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.keyPrefix = 'club-profile-tab',
    this.compact = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final String keyPrefix;

  /// A secondary switch inside a tab — the Events tab's Upcoming / Past —
  /// reads as one level down from the frame's own 38pt tab track.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 36 : 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ClubProfileColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ClubProfileColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey('$keyPrefix-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Container(
                  height: compact ? 28 : 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index
                        ? ClubProfileColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: figtree(
                      size: 13,
                      weight: i == index ? FontWeight.w700 : FontWeight.w600,
                      color: i == index
                          ? Colors.white
                          : ClubProfileColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── streams ──────────────────────────────────────────────────────────────────

/// `post-card-photo` `341:7` and `post-card-0` `337:57` — one card that grows
/// a photo when the post has one.
class ClubProfilePostCard extends StatelessWidget {
  const ClubProfilePostCard({
    super.key,
    required this.avatar,
    required this.authorName,
    required this.timeLabel,
    required this.body,
    this.image,
    this.pinned = false,
    this.onTap,
    this.menu,
  });

  final Widget avatar;
  final String authorName;
  final String timeLabel;
  final String body;

  /// Already-resolved banner for the post's photo, sized by this card.
  final Widget? image;
  final bool pinned;
  final VoidCallback? onTap;

  /// The frame's `more-horizontal`, supplied by the caller so the moderation
  /// menu stays with the screen that owns those actions. Absent for anyone who
  /// cannot moderate.
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    return ClubProfileCard(
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 36, height: 36, child: ClipOval(child: avatar)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: figtree(
                        size: 14,
                        weight: FontWeight.w700,
                        color: ClubProfileColors.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (pinned) ...[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 11,
                            color: ClubProfileColors.accentText,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: figtree(
                              size: 11.5,
                              weight: pinned
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: pinned
                                  ? ClubProfileColors.accentText
                                  : ClubProfileColors.muted,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ?menu,
            ],
          ),
          if (body.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              body,
              style: figtree(
                size: 13.5,
                weight: FontWeight.w400,
                color: ClubProfileColors.text,
                height: 1.45,
              ),
            ),
          ],
          if (image != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: image,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact club-profile event row, aligned with the app's Events tab: square
/// cover on the left, a small date/time pill, title and location on the right.
class ClubProfileEventCard extends StatelessWidget {
  const ClubProfileEventCard({
    super.key,
    required this.cover,
    required this.title,
    required this.dateLabel,
    required this.timeLabel,
    required this.location,
    this.statusLabel,
    this.audienceBadge,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.onLongPress,
  });

  final Widget cover;
  final String title;
  final String dateLabel;
  final String timeLabel;
  final String location;

  /// HAPPENING NOW / PAST, which the frame has no cell for but the app does.
  final String? statusLabel;

  /// The `ContentAudiencePill` for a restricted event, supplied by the screen
  /// so this widget keeps knowing nothing about the audience model — the same
  /// division [menu] observes on the post card. Null for a public event.
  final Widget? audienceBadge;

  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  /// The frame draws no control on an event card, so the club's delete action
  /// hangs off a long press — the same move the board rows make.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return ClubProfileCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 96, height: 96, child: cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // A Wrap rather than a Row: with a status chip and an
                // audience badge alongside it this line can carry three chips,
                // and a narrow phone in Turkish does not fit them on one.
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ClubProfileColors.accentSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$dateLabel · $timeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: figtree(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: ClubProfileColors.accentText,
                        ),
                      ),
                    ),
                    if (statusLabel != null)
                      ClubProfileChip(label: statusLabel!),
                    ?audienceBadge,
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: ClubProfileColors.text,
                    height: 1.2,
                    letterSpacing: -0.1,
                  ),
                ),
                if (location.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: ClubProfileColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: figtree(
                            size: 11.5,
                            weight: FontWeight.w500,
                            color: ClubProfileColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: onAction != null,
            label: actionLabel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: SizedBox(
                width: 24,
                height: 40,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: ClubProfileColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `rsvp-button` `343:82` — a full-width 36pt accent button.
class ClubProfilePrimaryButton extends StatelessWidget {
  const ClubProfilePrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ClubProfileColors.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: figtree(
            size: 13,
            weight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// `board-header` `332:2013` and `Post Performance` `347:64` — an ExtraBold
/// label with an accent action on the right.
class ClubProfileSectionHeader extends StatelessWidget {
  const ClubProfileSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.rule = false,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The insights frame draws a hairline under this header; the board one
  /// does not.
  final bool rule;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: figtree(
                  size: 16,
                  weight: FontWeight.w800,
                  color: ClubProfileColors.text,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (actionLabel != null)
              GestureDetector(
                key: const ValueKey('club-profile-section-action'),
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: Text(
                  actionLabel!,
                  style: figtree(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: ClubProfileColors.accentText,
                  ),
                ),
              ),
          ],
        ),
        if (rule) ...[
          const SizedBox(height: 10),
          Container(height: 1, color: ClubProfileColors.border),
        ],
      ],
    );
  }
}

/// `member-row` `332:2017` — 44pt photo, name, role, optional chevron.
class ClubProfileMemberRow extends StatelessWidget {
  const ClubProfileMemberRow({
    super.key,
    required this.avatar,
    required this.name,
    required this.role,
    this.onTap,
    this.onLongPress,
    this.showChevron = false,
  });

  final Widget avatar;
  final String name;
  final String role;
  final VoidCallback? onTap;

  /// The frames draw no per-row controls, so the club's edit-title / remove
  /// actions hang off a long press instead of a visible affordance.
  final VoidCallback? onLongPress;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return ClubProfileCard(
      radius: 14,
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(width: 44, height: 44, child: ClipOval(child: avatar)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 14,
                    weight: FontWeight.w700,
                    color: ClubProfileColors.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 12,
                    weight: FontWeight.w500,
                    color: ClubProfileColors.muted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: ClubProfileColors.muted,
            ),
          ],
        ],
      ),
    );
  }
}

/// `search-bar` `346:28` — a clean 44pt field with no fill or outline.
class ClubProfileSearchField extends StatelessWidget {
  const ClubProfileSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 18,
              color: ClubProfileColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: figtree(
                  size: 13.5,
                  weight: FontWeight.w500,
                  color: ClubProfileColors.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: hint,
                  hintStyle: figtree(
                    size: 13.5,
                    weight: FontWeight.w400,
                    color: ClubProfileColors.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── insights ─────────────────────────────────────────────────────────────────

/// `metrics-grid` cell `347:30` — a tinted 28pt icon tile above the number.
class ClubProfileMetricTile extends StatelessWidget {
  const ClubProfileMetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClubProfileCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: ClubProfileColors.accentSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: ClubProfileColors.accentText),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: figtree(
              size: 22,
              weight: FontWeight.w800,
              color: ClubProfileColors.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: figtree(
              size: 12,
              weight: FontWeight.w500,
              color: ClubProfileColors.muted,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// `Post Performance` row `347:69` — thumbnail, title, date, likes and views.
class ClubProfilePostStatRow extends StatelessWidget {
  const ClubProfilePostStatRow({
    super.key,
    required this.thumbnail,
    required this.title,
    required this.dateLabel,
    required this.likes,
    required this.views,
    this.onTap,
  });

  final Widget thumbnail;
  final String title;
  final String dateLabel;
  final String likes;
  final String views;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClubProfileCard(
      radius: 14,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 44, height: 44, child: thumbnail),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 14,
                    weight: FontWeight.w700,
                    color: ClubProfileColors.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 12,
                    weight: FontWeight.w500,
                    color: ClubProfileColors.muted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _metric(Icons.favorite_border_rounded, likes),
          const SizedBox(width: 12),
          _metric(Icons.visibility_outlined, views),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: ClubProfileColors.muted),
        const SizedBox(width: 4),
        Text(
          value,
          style: figtree(
            size: 12,
            weight: FontWeight.w600,
            color: ClubProfileColors.muted,
          ),
        ),
      ],
    );
  }
}

/// Shared empty state for a tab with nothing in it — the frames draw none, so
/// this keeps the area's own type and colours rather than borrowing another's.
class ClubProfileEmptyState extends StatelessWidget {
  const ClubProfileEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: ClubProfileColors.muted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: figtree(
              size: 15,
              weight: FontWeight.w700,
              color: ClubProfileColors.text,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: figtree(
                size: 12.5,
                weight: FontWeight.w400,
                color: ClubProfileColors.muted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

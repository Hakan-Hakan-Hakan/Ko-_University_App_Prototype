import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/club.dart';
import '../models/content_audience.dart';
import '../models/event.dart';
import '../services/content_visibility.dart';
import '../services/locale_service.dart';
import '../services/photo_file_cache.dart';
import '../services/theme_service.dart';
import '../theme/specialized_semantic_palettes.dart';
import '../services/user_state.dart';
import 'app_network_image.dart';
import 'clubup_design.dart';
import 'content_audience_sheet.dart';
import 'event_cover_image.dart';
import 'loading_skeleton.dart';
import 'user_avatar.dart';

/// The STUDENT PROFİLE area of the ClubUp-Desings handoff — `profile-screen`
/// (Figma `59:6` / `59:114`) and `profile-menu` (`241:6` / `241:113`).
///
/// Like every other redesigned area these widgets are deliberately *local*:
/// only [StudentProfileScreen] and [UserProfileScreen] draw them.
/// `student_campus_profile.dart` is left exactly as it was, because
/// `student_activity_screen.dart` and `student_activity_section.dart` still
/// render its palette and section labels and their frames have not been
/// reviewed yet.
///
/// Typography comes from [figtree] in `clubup_design.dart`. Colors do **not**
/// — see [ProfileColors].

// ── tokens ───────────────────────────────────────────────────────────────────

/// Palette for the profile frames.
///
/// Light is identical to [ClubUpColors]. Dark is **not**: the profile frames
/// (and, as it turns out, the HOME frames too) are painted on zinc-950 /
/// zinc-900 / zinc-800 — `#09090B` page, `#18181B` card, `#27272A` hairline —
/// whereas [ClubUpColors] carries the `#121212` / `#1E1E1E` / `#2D2D2D` set an
/// earlier area approximated. Correcting [ClubUpColors] in place would restyle
/// Search, Events and Home in dark mode, none of which was part of this pass,
/// so the true handoff values live here until someone reconciles the two.
///
/// The other divergence: accent text stays `#800020` in dark on these frames.
/// There is no lifted `#E8A1A6` anywhere in `profile-screen-dark` —
/// sampling it turns up exactly one accent, the same burgundy as light.
class ProfileColors {
  const ProfileColors._();

  static SpecializedSemanticPalette of(BuildContext context) =>
      SpecializedSemanticPalettes.profiles(Theme.of(context));

  static bool get _dark => themeService.isDark;

  /// Page background — `#FAF9F6` / `#09090B`.
  static Color get background =>
      _dark ? const Color(0xFF09090B) : const Color(0xFFFAF9F6);

  /// Card surface — `#FFFFFF` / `#18181B`.
  static Color get card => _dark ? const Color(0xFF18181B) : Colors.white;

  /// Hairline around cards, and the stats-row rules — `#E4E4E7` / `#27272A`.
  static Color get border =>
      _dark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);

  /// Primary text — `#18181B` / `#FAFAFA`.
  static Color get text =>
      _dark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);

  /// Secondary text — `#71717A` / `#A1A1AA`.
  static Color get muted =>
      _dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);

  /// The one accent, unchanged between themes.
  static const Color accent = Color(0xFF800020);

  /// `rgba(128, 0, 32, 0.14)` — the "Follows you" badge and the pressed
  /// overflow button.
  static const Color accentWash = Color(0x24800020);

  /// The destructive row in the overflow menu — `#EF4444`.
  static const Color danger = Color(0xFFEF4444);

  /// The 1px rule between overflow-menu rows — `#F4F4F5`.
  static Color get menuDivider =>
      _dark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5);

  /// `drop-shadow(0 8px 12px rgba(0, 0, 0, 0.11))` under the overflow menu.
  static List<BoxShadow> get menuShadow => [
    BoxShadow(
      color: _dark ? const Color(0x66000000) : const Color(0x1C000000),
      offset: const Offset(0, 8),
      blurRadius: 12,
    ),
  ];

  /// Behind the open overflow menu: `rgba(0, 0, 0, 0.24)` on `profile-menu-
  /// light`. The dark frame dims harder — sampling it, the page, the card and
  /// the accent all sit at 60% of their unscrimmed values.
  static Color get scrim =>
      _dark ? const Color(0x66000000) : const Color(0x3D000000);
}

/// Horizontal page padding on both frames — `px-[24px]`.
const double kProfilePagePadding = 24;

/// `pb-[120px]`: the frames leave room for the floating bottom nav that
/// `main_nav_screen.dart` draws over this screen.
const double kProfileNavClearance = 120;

/// The `@handle` line. Students have no handle field, so the local part of the
/// KU address stands in for one — the same substitution the search area makes.
String profileHandle(String email) {
  final local = email.split('@').first.trim();
  return local.isEmpty ? '' : '@$local';
}

/// The `event-card` date line — "Today · 19:00", "Tomorrow · 20:00", or
/// "Fri 12 · 19:00" once it is further out. The frames read "Tonight · 7 PM";
/// the app is on 24-hour time and localises its day names, so the shape is
/// kept and the values come from the real event.
String profileWhenLabel(
  BuildContext context,
  DateTime when, {
  bool live = false,
}) {
  final l10n = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final isToday =
      when.year == now.year && when.month == now.month && when.day == now.day;
  final tomorrow = now.add(const Duration(days: 1));
  final isTomorrow =
      when.year == tomorrow.year &&
      when.month == tomorrow.month &&
      when.day == tomorrow.day;
  final day = isToday
      ? l10n.today
      : isTomorrow
      ? l10n.tomorrow
      : '${DateFormat.E(localeService.languageCode).format(when)} ${when.day}';
  final time = live
      ? l10n.liveNowFilterLabel
      : '${when.hour.toString().padLeft(2, '0')}:'
            '${when.minute.toString().padLeft(2, '0')}';
  return '$day · $time';
}

// ── header chrome ────────────────────────────────────────────────────────────

/// `btn-share` / `btn-back` / `btn-more`: a circular icon button. [washed]
/// fills it with [ProfileColors.accentWash] the way `btn-more` is filled while
/// its menu is open.
class ProfileCircleButton extends StatelessWidget {
  const ProfileCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 34,
    this.iconSize = 18,
    this.washed = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool washed;

  @override
  Widget build(BuildContext context) {
    Widget button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: washed ? ProfileColors.accentWash : ProfileColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: ProfileColors.accent, width: 1.5),
        ),
        child: Icon(icon, size: iconSize, color: ProfileColors.accent),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(button: true, label: tooltip, child: button);
  }
}

/// `settings-button` — the neutral rounded square beside the share circle.
class ProfileSquareButton extends StatelessWidget {
  const ProfileSquareButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ProfileColors.card,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: ProfileColors.border),
        ),
        child: Icon(icon, size: 20, color: ProfileColors.text),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(button: true, label: tooltip, child: button);
  }
}

/// `header` on `profile-screen`: the two-tone wordmark, then share + settings.
class ProfileWordmarkHeader extends StatelessWidget {
  const ProfileWordmarkHeader({
    super.key,
    required this.onShare,
    required this.onSettings,
    this.shareTooltip,
    this.settingsTooltip,
  });

  final VoidCallback? onShare;
  final VoidCallback? onSettings;
  final String? shareTooltip;
  final String? settingsTooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kProfilePagePadding,
        vertical: 12,
      ),
      child: Row(
        children: [
          Text.rich(
            key: const ValueKey('profile-clubup-logo'),
            TextSpan(
              children: [
                TextSpan(
                  text: 'Club',
                  style: figtree(
                    size: 22,
                    weight: FontWeight.w800,
                    color: ProfileColors.accent,
                  ),
                ),
                TextSpan(
                  text: 'Up',
                  style: figtree(
                    size: 22,
                    weight: FontWeight.w800,
                    color: ProfileColors.text,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          ProfileCircleButton(
            icon: Icons.ios_share_rounded,
            iconSize: 18,
            size: 36,
            tooltip: shareTooltip,
            onTap: onShare,
          ),
          const SizedBox(width: 8),
          ProfileSquareButton(
            icon: Icons.settings_outlined,
            tooltip: settingsTooltip,
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

/// `header` on `profile-menu`: back chevron, `@handle` title, trailing action.
class ProfileBackHeader extends StatelessWidget {
  const ProfileBackHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.backTooltip,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final String? backTooltip;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(
        horizontal: kProfilePagePadding,
        vertical: 12,
      ),
      child: Row(
        children: [
          ProfileCircleButton(
            icon: Icons.chevron_left_rounded,
            iconSize: 22,
            tooltip: backTooltip,
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figtree(
                size: 20,
                weight: FontWeight.w800,
                color: ProfileColors.text,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ── hero ─────────────────────────────────────────────────────────────────────

/// `avatar-wrapper` — a compact 74px circular portrait.
class ProfileAvatarRing extends StatelessWidget {
  const ProfileAvatarRing({
    super.key,
    required this.userId,
    required this.name,
    this.size = 74,
    this.onTap,
  });

  final String userId;
  final String name;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipOval(
        child: UserAvatar(
          userId: userId,
          name: name,
          size: size,
          fontSize: size / 2.9,
        ),
      ),
    );
  }
}

/// One cell of `stats-row`.
class ProfileStat extends StatelessWidget {
  const ProfileStat({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Text(
              value,
              style: figtree(
                size: 13,
                weight: FontWeight.w800,
                color: ProfileColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: figtree(
                size: 11,
                weight: FontWeight.w500,
                color: ProfileColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `stats-row` — three equal cells between two hairlines.
class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({super.key, required this.stats});

  final List<ProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: ProfileColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: stats),
    );
  }
}

/// `profile-hero` — avatar, name, optional handle (+ optional badge), bio,
/// stats and, on `profile-menu`, the Follow / Message pair.
class ProfileHero extends StatelessWidget {
  const ProfileHero({
    super.key,
    required this.userId,
    required this.name,
    required this.handle,
    required this.bio,
    required this.stats,
    this.badgeLabel,
    this.nameBadge,
    this.gap = 16,
    this.identityGap = 4,
    this.actions,
    this.onAvatarTap,
  });

  final String userId;
  final String name;
  final String handle;
  final String bio;
  final List<ProfileStat> stats;

  /// `badge` beside the handle — "Follows you" on `profile-menu`. The signed-in
  /// student's own profile supplies no handle, so this identity line collapses.
  final String? badgeLabel;

  /// `board-badge` — the capsule the frame centres between the name and the
  /// bio. Only students who hold a board role anywhere carry one, so it is
  /// null for everyone else and the hero closes the gap.
  final Widget? nameBadge;

  /// `gap-[16px]` on `profile-screen`, `gap-[14px]` on `profile-menu`.
  final double gap;

  /// `identity` gap: 4 on `profile-screen`, 6 on `profile-menu`.
  final double identityGap;

  final Widget? actions;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final hasIdentityLine = handle.trim().isNotEmpty || badgeLabel != null;
    final handleStyle = figtree(
      size: badgeLabel == null ? 14 : 13,
      weight: badgeLabel == null ? FontWeight.w500 : FontWeight.w400,
      color: ProfileColors.muted,
    );

    return Column(
      children: [
        ProfileAvatarRing(userId: userId, name: name, onTap: onAvatarTap),
        SizedBox(height: gap),
        Text(
          name,
          textAlign: TextAlign.center,
          style: figtree(
            size: 20,
            weight: FontWeight.w800,
            color: ProfileColors.text,
          ),
        ),
        if (nameBadge != null) ...[
          SizedBox(height: identityGap + 4),
          nameBadge!,
        ],
        if (hasIdentityLine) ...[
          SizedBox(height: identityGap),
          if (badgeLabel == null)
            Text(handle, textAlign: TextAlign.center, style: handleStyle)
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: handleStyle,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: ProfileColors.accentWash,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Text(
                    badgeLabel!,
                    style: figtree(
                      size: 11,
                      weight: FontWeight.w700,
                      color: ProfileColors.accent,
                    ),
                  ),
                ),
              ],
            ),
        ],
        if (bio.trim().isNotEmpty) ...[
          SizedBox(height: gap),
          Text(
            bio.trim(),
            textAlign: TextAlign.center,
            style: figtree(
              size: 14,
              weight: FontWeight.w400,
              color: ProfileColors.text,
              height: 1.4,
            ),
          ),
        ],
        SizedBox(height: gap),
        ProfileStatsRow(stats: stats),
        if (actions != null) ...[SizedBox(height: gap), actions!],
      ],
    );
  }
}

/// `board-badge` on `profile-screen`, and the trailing chip on every row of
/// `board-memberships-overlay`.
///
/// One capsule serves both: the accent wash behind an accent hairline. The
/// label is accent in light and the page's primary text in dark — sampling the
/// frames, the dark capsule writes in near-white over the same wash, which is
/// the only way `#800020` on `#09090B` stays readable at 11px.
class ProfileRolePill extends StatelessWidget {
  const ProfileRolePill({
    super.key,
    required this.label,
    this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onTap;

  /// Announced instead of [label] when the capsule is a button — the badge
  /// under the name opens `board-memberships-overlay`.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: ProfileColors.accentWash,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: ProfileColors.accent),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: figtree(
          size: 11,
          weight: FontWeight.w700,
          color: themeService.isDark
              ? ProfileColors.text
              : ProfileColors.accent,
        ),
      ),
    );

    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: pill,
      ),
    );
  }
}

// ── section chrome ───────────────────────────────────────────────────────────

/// `section-header` — an ExtraBold title and an accent "See All".
class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: figtree(
              size: 16,
              weight: FontWeight.w800,
              color: ProfileColors.text,
            ),
          ),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Text(
              actionLabel!,
              style: figtree(
                size: 13,
                weight: FontWeight.w700,
                color: ProfileColors.accent,
              ),
            ),
          ),
      ],
    );
  }
}

// ── club card ────────────────────────────────────────────────────────────────

/// `club-card` — a 90px cover, the club name and its member count.
///
/// `w-[140px]` in `my-clubs-section`, `w-[150px]` in `mutual-clubs`.
class ProfileClubCard extends StatelessWidget {
  const ProfileClubCard({
    super.key,
    required this.club,
    required this.color,
    required this.detail,
    this.width = 140,
    this.nameSize = 13,
    this.onTap,
  });

  final Club club;
  final Color color;
  final String detail;
  final double width;

  /// 13 Bold on `profile-screen`, 11 SemiBold on `profile-menu`.
  final double nameSize;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ProfileColors.card,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: ProfileColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileClubCover(
              club: club,
              color: color,
              width: width - 24,
              height: 90,
            ),
            const SizedBox(height: 8),
            Text(
              club.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figtree(
                size: nameSize,
                weight: nameSize >= 13 ? FontWeight.w700 : FontWeight.w600,
                color: ProfileColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figtree(
                size: 11,
                weight: FontWeight.w400,
                color: ProfileColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `club-image`. Clubs have no cover field — only `logoUrl` and whatever photo
/// the club admin set — so this resolves the same chain [EventCoverImage] uses
/// for a club and falls back to a burgundy wash with the club's initials.
class ProfileClubCover extends StatelessWidget {
  const ProfileClubCover({
    super.key,
    required this.club,
    required this.color,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  final Club club;
  final Color color;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final path = _coverPath();
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
      child: SizedBox(
        width: width,
        height: height,
        child: path == null
            ? _fallback()
            : _isRemote(path)
            ? AppNetworkImage(
                url: path,
                width: width,
                height: height,
                cacheWidth: width * 2,
                cacheHeight: height * 2,
                fit: BoxFit.cover,
                placeholderBuilder: (_) => const SkeletonBox(),
                errorBuilder: (_) => _fallback(),
              )
            : Image.file(
                File(path),
                width: width,
                height: height,
                cacheWidth: (width * dpr).round(),
                cacheHeight: (height * dpr).round(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.88),
            ProfileColors.accent.withValues(alpha: 0.72),
          ],
        ),
      ),
      child: Center(
        child: Text(
          clubInitials(club),
          style: figtree(
            size: height / 3.4,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  String? _coverPath() {
    final candidates = <String?>[
      userState.clubPhotoPaths[club.id],
      userState.remoteClubPhotoUrls[club.id],
      club.logoUrl,
      for (final adminId in club.adminUserIds)
        userState.profilePhotoPaths[adminId],
      for (final adminId in club.adminUserIds)
        userState.remotePhotoUrls[adminId],
    ];
    for (final raw in candidates) {
      final path = raw?.trim() ?? '';
      if (path.isEmpty) continue;
      if (_isRemote(path) || photoFileCache.existsSync(path)) return path;
    }
    return null;
  }

  bool _isRemote(String path) =>
      path.startsWith('http://') || path.startsWith('https://');
}

/// The club's initials, for [ProfileClubCover]'s fallback. `clubHandle` is the
/// `@`-form; this is the display form.
String clubInitials(Club club) {
  final words = club.name.split(RegExp(r'[\s\-]+'));
  final initials = words
      .where((w) => w.isNotEmpty)
      .map((w) => w[0])
      .take(2)
      .join()
      .toUpperCase();
  return initials.isEmpty ? '?' : initials;
}

// ── event card ───────────────────────────────────────────────────────────────

/// `event-card` — a 64px thumbnail, the title, a calendar line and, on
/// `profile-screen`, an accent line naming the hosting club.
class ProfileEventCard extends StatelessWidget {
  const ProfileEventCard({
    super.key,
    required this.event,
    required this.color,
    required this.whenLabel,
    this.clubName,
    this.onTap,
  });

  final Event event;
  final Color color;
  final String whenLabel;

  /// Omitted on `profile-menu`, where the card shows only the date line.
  final String? clubName;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ProfileColors.card,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: ProfileColors.border),
        ),
        child: Row(
          children: [
            EventCoverImage(
              event: event,
              color: color,
              width: 64,
              height: 64,
              cacheWidth: 128,
              cacheHeight: 128,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: clubName == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: figtree(
                      size: 14,
                      weight: FontWeight.w700,
                      color: ProfileColors.text,
                    ),
                  ),
                  SizedBox(height: clubName == null ? 5 : 4),
                  _MetaLine(
                    icon: Icons.calendar_today_rounded,
                    label: whenLabel,
                    size: 12,
                    weight: FontWeight.w400,
                    color: ProfileColors.muted,
                    gap: clubName == null ? 6 : 4,
                  ),
                  if (clubName != null) ...[
                    const SizedBox(height: 4),
                    _MetaLine(
                      icon: Icons.group_outlined,
                      label: clubName!,
                      size: 11,
                      weight: FontWeight.w600,
                      color: ProfileColors.accent,
                      gap: 4,
                    ),
                  ],
                  // `ProfileColors` has no lifted accent-text token, so the
                  // badge borrows the same `accent` the club line above it
                  // already uses as text on this card.
                  if (audienceForEvent(event) != ContentAudience.everyone) ...[
                    const SizedBox(height: 6),
                    ContentAudiencePill(
                      key: ValueKey('content-audience-pill-${event.id}'),
                      audience: audienceForEvent(event),
                      accent: ProfileColors.accent,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.icon,
    required this.label,
    required this.size,
    required this.weight,
    required this.color,
    required this.gap,
  });

  final IconData icon;
  final String label;
  final double size;
  final FontWeight weight;
  final Color color;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        SizedBox(width: gap),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: figtree(size: size, weight: weight, color: color),
          ),
        ),
      ],
    );
  }
}

// ── actions ──────────────────────────────────────────────────────────────────

/// `btn-follow` / `btn-message` — a 46px pill pair, one filled, one outlined.
class ProfileActionButton extends StatelessWidget {
  const ProfileActionButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
    this.iconSize = 18,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final IconData? icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : ProfileColors.text;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? ProfileColors.accent : Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: filled ? null : Border.all(color: ProfileColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: iconSize, color: foreground),
              const SizedBox(width: 6),
            ],
            // "Follow back" in Turkish is half again as long as in English, and
            // the pair splits a 393pt frame in two, so the label has to give.
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

// ── overflow menu ────────────────────────────────────────────────────────────

/// One row of `dropdown-menu`.
class ProfileMenuAction {
  const ProfileMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// `menu-item-ban` — `#EF4444`, SemiBold.
  final bool destructive;
}

/// `dropdown-menu` + `scrim-overlay`: the anchored card that replaces the old
/// safety bottom sheet. Anchored under the header's overflow button rather than
/// at a fixed `top-[100px]`, so it lands in the right place on every device.
Future<void> showProfileOverflowMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<ProfileMenuAction> actions,
}) {
  final anchor = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final top = anchor != null && overlay != null
      ? anchor
            .localToGlobal(Offset(0, anchor.size.height + 8), ancestor: overlay)
            .dy
      : 100.0;

  return showGeneralDialog<void>(
    context: context,
    barrierColor: ProfileColors.scrim,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, animation, _) {
      return Stack(
        children: [
          Positioned(
            top: top,
            right: 16,
            child: FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                alignment: Alignment.topRight,
                scale: Tween<double>(begin: 0.94, end: 1).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: _ProfileOverflowCard(actions: actions),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ProfileOverflowCard extends StatelessWidget {
  const _ProfileOverflowCard({required this.actions});

  final List<ProfileMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      // The frame's card is a flat `w-[180px]`, which fits "Ban User" but
      // ellipsises the app's real destructive label. It grows to fit instead,
      // and never past 260 so it stays a menu rather than a sheet.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: ProfileColors.card,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              border: Border.all(color: ProfileColors.border),
              boxShadow: ProfileColors.menuShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0)
                    Container(height: 1, color: ProfileColors.menuDivider),
                  _ProfileMenuRow(action: actions[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({required this.action});

  final ProfileMenuAction action;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive
        ? ProfileColors.danger
        : ProfileColors.text;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        action.onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(action.icon, size: 18, color: color),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: figtree(
                  size: 14,
                  weight: action.destructive
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── empty state ──────────────────────────────────────────────────────────────

/// There is no empty-state frame for the two sections, so a section with
/// nothing in it simply doesn't render — except on your own profile, where a
/// single quiet line keeps the page from looking broken on a fresh account.
class ProfileSectionEmptyLine extends StatelessWidget {
  const ProfileSectionEmptyLine({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: ProfileColors.card,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: ProfileColors.border),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: figtree(
          size: 13,
          weight: FontWeight.w500,
          color: ProfileColors.muted,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/content_audience.dart';
import '../services/app_strings.dart';
import 'clubup_design.dart';

/// The one audience picker, shared by the post composer and the event wizard.
///
/// Those two screens live in different palette worlds — the composer is on the
/// legacy warm `AppColors` set, the wizard on `EventWizardColors` with its
/// lifted dark accent — and neither owns the other's tokens. Rather than fork
/// the sheet or reach across areas, the caller passes its own five colours in.
/// The chrome reproduces the event wizard's sheet (radius-32 top, a 36×5 handle,
/// a 24/12 padded title row) because that is the established sheet shape in this
/// flow, but it does not import the wizard's private `_WizardSheet`.
///
/// Tapping an option pops with it, so there is no Done pill to plumb and one
/// fewer tap than the date and time sheets need. Returns null when dismissed.
Future<ContentAudience?> showContentAudienceSheet(
  BuildContext context, {
  required ContentAudience current,
  required Color surface,
  required Color border,
  required Color text,
  required Color muted,
  required Color accent,
}) {
  return showModalBottomSheet<ContentAudience>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (sheetContext) => _ContentAudienceSheet(
      current: current,
      surface: surface,
      border: border,
      text: text,
      muted: muted,
      accent: accent,
    ),
  );
}

class _ContentAudienceSheet extends StatelessWidget {
  const _ContentAudienceSheet({
    required this.current,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
  });

  final ContentAudience current;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('content-audience-sheet'),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: muted,
                  borderRadius: const BorderRadius.all(Radius.circular(100)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      S.audienceSheetTitle,
                      style: figtree(
                        size: 16,
                        weight: FontWeight.w700,
                        color: text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final audience in ContentAudience.values)
              _AudienceOptionRow(
                audience: audience,
                selected: audience == current,
                text: text,
                muted: muted,
                accent: accent,
                onTap: () => Navigator.pop(context, audience),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// One option: a ring, the tier name, and the line that says who that actually
/// means. The description is the reason this is not the app's existing radio
/// row — "Followers" alone does not tell a club president what they are picking.
class _AudienceOptionRow extends StatelessWidget {
  const _AudienceOptionRow({
    required this.audience,
    required this.selected,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onTap,
  });

  final ContentAudience audience;
  final bool selected;
  final Color text;
  final Color muted;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: ValueKey('content-audience-option-${audience.wireValue}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? accent : muted,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          key: ValueKey(
                            'content-audience-selected-${audience.wireValue}',
                          ),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      S.audienceTierLabel(audience),
                      style: figtree(
                        size: 14,
                        weight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      S.audienceTierHint(audience),
                      style: figtree(
                        size: 12,
                        weight: FontWeight.w400,
                        color: muted,
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

/// The glyph that stands for a tier.
///
/// A padlock for the board tier and a pair of people for followers, rather than
/// one generic eye for both. The badge has to carry its meaning at 12-14px,
/// which on a dense event row or a photo overlay is all the reader really
/// registers before the label.
IconData audienceTierIcon(ContentAudience audience) => switch (audience) {
  ContentAudience.everyone => Icons.public,
  ContentAudience.followers => Icons.group_outlined,
  ContentAudience.board => Icons.lock_outline,
};

/// The badge a restricted post or event carries on its card, so a club can tell
/// at a glance that something is not public. Renders nothing for
/// [ContentAudience.everyone] — public content is the overwhelming majority and
/// a badge on all of it would say nothing.
///
/// Two variants, because the app shows restricted content on two kinds of
/// surface:
///
/// * The default **tinted chip** for a writing area — a 10% wash of whatever
///   accent the host area owns, matching the announcement chip it sits beside.
///   Areas whose accent is not legible as text (`ClubUpColors.accent` fails
///   contrast on a dark card, which is why `accentText` exists) pass the
///   readable colour as [foreground].
/// * [ContentAudiencePill.onMedia] for a badge laid over a cover photo, where a
///   10% wash of anything is invisible. That variant reproduces the event
///   hero's own `_StatusPill` — a solid scrim, white text, fully rounded — so
///   the two read as one family when they sit side by side.
///
/// Sized to its label, so give it a bounded line: it belongs in a [Wrap], a
/// [Flexible], or a [Positioned] over media, never as the widening child of a
/// [Row].
class ContentAudiencePill extends StatelessWidget {
  const ContentAudiencePill({
    super.key,
    required this.audience,
    required Color accent,
    Color? foreground,
  }) : _tint = accent,
       _label = foreground ?? accent,
       _onMedia = false;

  /// The over-a-photo variant. Takes no accent: a cover image is arbitrary, so
  /// the badge brings its own contrast rather than borrowing the club's colour.
  const ContentAudiencePill.onMedia({super.key, required this.audience})
    : _tint = const Color(0x8C000000),
      _label = Colors.white,
      _onMedia = true;

  final ContentAudience audience;

  /// Fill colour — washed to 10% on a card, used as-is over media.
  final Color _tint;

  /// Icon and text colour.
  final Color _label;

  final bool _onMedia;

  @override
  Widget build(BuildContext context) {
    if (audience == ContentAudience.everyone) return const SizedBox.shrink();
    return Container(
      padding: _onMedia
          ? const EdgeInsets.symmetric(horizontal: 9, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _onMedia ? _tint : _tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.all(Radius.circular(_onMedia ? 999 : 8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            audienceTierIcon(audience),
            size: _onMedia ? 11 : 13,
            color: _label,
          ),
          const SizedBox(width: 5),
          Text(
            S.audienceTierPill(audience),
            maxLines: 1,
            softWrap: false,
            style: figtree(
              size: _onMedia ? 9.5 : 11,
              weight: _onMedia ? FontWeight.w800 : FontWeight.w700,
              color: _label,
              letterSpacing: _onMedia ? 0.6 : null,
            ),
          ),
        ],
      ),
    );
  }
}

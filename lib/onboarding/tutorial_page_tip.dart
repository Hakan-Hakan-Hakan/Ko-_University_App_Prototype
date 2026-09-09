import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/tutorial_design.dart';
import 'widgets/onboarding_guide_card.dart';
import '../services/guest_session.dart';

/// Page-level tips — `panel-behaviour` `392:24`: "A student who skipped still
/// gets the single card for a page the first time they open it, so nothing
/// essential is lost to one tap."
///
/// These are not tour stops. They are one card, with the page name as the
/// eyebrow, no progress dots, no Back, and a single Got it.
///
/// **Storage is device-local only.** Which tips a student has seen lives in
/// [SharedPreferences] and nowhere else — there is no table, column or sync
/// for it. [OnboardingService] persists first-run completion to Supabase, but
/// deliberately nothing here does: a tip re-appearing on a second device is a
/// far smaller cost than a schema change.
class TutorialPageTips {
  TutorialPageTips();

  /// `tut-announcements` 389:2162 — the pinned-notices lane of a club room.
  static const String announcements = 'announcements';

  static const String _seenPrefix = 'tutorial_page_tip_seen_';
  static const String _offKey = 'tutorial_page_tips_off';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  /// True when [id] has never been shown and tips have not been switched off.
  Future<bool> shouldShow(String id) async {
    final prefs = await _prefs;
    if (prefs.getBool(_offKey) == true) return false;
    return prefs.getBool('$_seenPrefix$id') != true;
  }

  Future<void> markSeen(String id) async {
    if (guestSession.isActive) return;
    final prefs = await _prefs;
    await prefs.setBool('$_seenPrefix$id', true);
  }

  /// "Skip tour ends the whole tour, not just the current page, and never asks
  /// a second time" — from a page tip that means no further tips either.
  Future<void> suppressAll() async {
    if (guestSession.isActive) return;
    final prefs = await _prefs;
    await prefs.setBool(_offKey, true);
  }

  @visibleForTesting
  Future<void> reset() async {
    if (guestSession.isActive) return;
    final prefs = await _prefs;
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_seenPrefix) || key == _offKey) {
        await prefs.remove(key);
      }
    }
  }
}

final tutorialPageTips = TutorialPageTips();

/// Stacks one page tip over the screen it belongs to: the same dimmed scrim
/// with a cut-out on [anchorKey], the same beak, and the same card.
///
/// Renders nothing at all until the anchor has been measured and the tip is
/// known to be unseen, so hosts can drop it into a [Stack] unconditionally.
class TutorialPageTipOverlay extends StatefulWidget {
  /// Which tip this is, for the seen-once bookkeeping.
  final String tipId;

  /// The element being taught. The tip waits for it to mount.
  final GlobalKey? anchorKey;

  /// Eyebrow, title and body, resolved lazily so a language switch is picked
  /// up on the next build.
  final String Function() pageLabel;
  final String Function() title;
  final String Function() body;

  final double spotlightRadius;

  /// False parks the tip entirely — a lane that is not on screen, a session
  /// that should not see it.
  final bool active;

  const TutorialPageTipOverlay({
    super.key,
    required this.tipId,
    required this.anchorKey,
    required this.pageLabel,
    required this.title,
    required this.body,
    this.spotlightRadius = TutorialMetrics.radiusCard,
    this.active = true,
  });

  @override
  State<TutorialPageTipOverlay> createState() => _TutorialPageTipOverlayState();
}

class _TutorialPageTipOverlayState extends State<TutorialPageTipOverlay> {
  bool _eligible = false;
  bool _dismissed = false;
  bool _checked = false;
  int _measureAttempt = 0;

  Rect? _hole;
  Size? _cardSize;
  final GlobalKey _cardMeasureKey = GlobalKey();
  bool _cardMeasureScheduled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void didUpdateWidget(covariant TutorialPageTipOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_checked) {
      unawaited(_check());
    }
    if (widget.active && _eligible && !_dismissed && _hole == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  Future<void> _check() async {
    if (!widget.active) return;
    _checked = true;
    final show = await tutorialPageTips.shouldShow(widget.tipId);
    if (!mounted || !show) return;
    setState(() => _eligible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  Future<void> _measure() async {
    if (!mounted || !_eligible || _dismissed) return;
    final anchorContext = widget.anchorKey?.currentContext;
    final overlayObject = context.findRenderObject();
    final anchorObject = anchorContext?.findRenderObject();
    if (anchorObject is! RenderBox ||
        overlayObject is! RenderBox ||
        !anchorObject.hasSize ||
        !overlayObject.hasSize) {
      // The lane may still be laying out. Give it a few frames, then give up
      // rather than dim the screen with nothing highlighted.
      if (_measureAttempt++ < 12) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (mounted) unawaited(_measure());
      }
      return;
    }
    final origin = overlayObject.globalToLocal(
      anchorObject.localToGlobal(Offset.zero),
    );
    final rect = origin & anchorObject.size;
    if (rect.isEmpty) return;
    setState(() => _hole = rect.inflate(TutorialMetrics.spotlightInset));
  }

  Future<void> _dismiss({required bool suppressEverything}) async {
    if (_dismissed) return;
    setState(() => _dismissed = true);
    HapticFeedback.selectionClick();
    if (suppressEverything) {
      await tutorialPageTips.suppressAll();
    } else {
      await tutorialPageTips.markSeen(widget.tipId);
    }
  }

  void _scheduleCardMeasurement() {
    if (_cardMeasureScheduled) return;
    _cardMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cardMeasureScheduled = false;
      if (!mounted) return;
      final box = _cardMeasureKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      if (_cardSize == null ||
          (box.size.height - _cardSize!.height).abs() > 0.5) {
        setState(() => _cardSize = box.size);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hole = _hole;
    if (!widget.active || !_eligible || _dismissed || hole == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final media = MediaQuery.of(context);
        final placement = placeTutorialCard(
          screen: size,
          safeArea: EdgeInsets.only(
            top: media.padding.top,
            bottom: media.viewInsets.bottom + media.padding.bottom,
          ),
          hole: hole,
          cardSize: Size(
            TutorialMetrics.cardWidth,
            _cardSize?.height ?? 190.0,
          ),
        );
        _scheduleCardMeasurement();

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: TutorialSpotlight(
                hole: hole,
                radius: widget.spotlightRadius,
              ),
            ),
            // The scrim swallows taps so the tip cannot be dismissed by
            // accident, and the cut-out is left alone so the notice under it
            // stays readable and tappable.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => HapticFeedback.selectionClick(),
              ),
            ),
            if (placement.beak != null)
              Positioned(
                left: placement.beak!.left,
                top: placement.beak!.top,
                width: TutorialMetrics.beakWidth,
                height: TutorialMetrics.beakHeight,
                child: IgnorePointer(
                  child: TutorialBeakView(beak: placement.beak!),
                ),
              ),
            Positioned(
              left: placement.card.left,
              top: placement.card.top,
              width: placement.card.width,
              child: KeyedSubtree(
                key: _cardMeasureKey,
                child: OnboardingGuideCard(
                  key: const ValueKey('tutorial-page-tip-card'),
                  eyebrow: widget.pageLabel(),
                  title: widget.title(),
                  body: widget.body(),
                  // A single-step page: no dots, no Back, and Got it.
                  isPageEnd: true,
                  onNext: () =>
                      unawaited(_dismiss(suppressEverything: false)),
                  onSkip: () => unawaited(_dismiss(suppressEverything: true)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

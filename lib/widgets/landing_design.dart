import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/theme_service.dart';
import 'clubup_design.dart';

/// `login-screen-light` / `login-screen` (Figma `495:5` / `485:5`) — the FİRST
/// LANDİNG PAGE section: the root screen that asks for a login, offers sign-up
/// and hides the club-admin portal in its footer.
///
/// Local to that screen, like every other redesigned area. `club_admin_auth_
/// screen.dart`, `platform_admin_auth_screen.dart` and `forgot_password_screen
/// .dart` still draw their own chrome — their frames have not been reviewed.

// ── tokens ───────────────────────────────────────────────────────────────────

/// A **third** page/surface ramp in this handoff: the landing frames are
/// painted on `#FAFAFA` / `#121212`, not the profile section's
/// `#FAF9F6` / `#09090B` nor the CHATS `#121212` / `#1A1A1A` pair. Sampled
/// straight out of the two PNGs rather than assumed.
class LandingColors {
  const LandingColors._();

  static bool get _dark => themeService.isDark;

  /// Page — `#FAFAFA` / `#121212`.
  static Color get background =>
      _dark ? const Color(0xFF121212) : const Color(0xFFFAFAFA);

  /// Input fill — `#FFFFFF` / `#1C1C1E`. The Sign Up button is *not* filled
  /// with this in dark: it sits flat on the page.
  static Color get field =>
      _dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);

  /// Hairline around inputs, the Sign Up button, the OR rules and the footer
  /// rule — `#E4E4E7` / `#2A2A2E`.
  static Color get border =>
      _dark ? const Color(0xFF2A2A2E) : const Color(0xFFE4E4E7);

  /// Primary text — `#18181B` / `#FAFAFA`.
  static Color get text =>
      _dark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);

  /// Placeholders — `#71717A` / `#A1A1AA`.
  static Color get placeholder =>
      _dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);

  /// The "OR" label — `#A1A1AA` / `#71717A`. The frames swap these two, which
  /// is why it is not [placeholder].
  static Color get subtle =>
      _dark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA);

  /// `Club Admin Portal` — `#A1A1AA` / `#3F3F46`. The dark frame keeps this
  /// link deliberately dim.
  static Color get footerLink =>
      _dark ? const Color(0xFF3F3F46) : const Color(0xFFA1A1AA);

  /// The wordmark, and the gradient's left stop.
  static const Color accent = Color(0xFF800020);

  /// The gradient's right stop.
  static const Color accentBright = Color(0xFFC71D49);

  /// `Forgot password?` — the one place the landing frames lift the accent in
  /// dark, exactly like `profile-settings` does with its icons.
  static Color get accentText =>
      _dark ? const Color(0xFFE8A1A6) : const Color(0xFF800020);

  /// The `language-switcher` track and its selected segment.
  static Color get segmentTrack =>
      _dark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5EA);
  static Color get segmentSelected =>
      _dark ? const Color(0xFF3A3A3A) : const Color(0xFFFFFFFF);

  /// `Log In` sits on a left-to-right burgundy → crimson ramp.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accent, accentBright],
  );
}

/// `content` is inset 32 on both sides — wider than the 24 the in-app frames
/// use, because this screen has no navigation chrome.
const double kLandingPagePadding = 32;

// ── language switcher ────────────────────────────────────────────────────────

/// `segmented-control` `515:19` — EN | TR in a filled track, split by a
/// hairline. Its own control rather than [LanguageToggle], which is shared with
/// the settings and onboarding screens.
class LandingLanguageToggle extends StatelessWidget {
  const LandingLanguageToggle({
    super.key,
    required this.languageCode,
    required this.onSelected,
  });

  final String languageCode;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: LandingColors.segmentTrack,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('EN', 'en'),
          Container(width: 1, height: 16, color: LandingColors.border),
          _segment('TR', 'tr'),
        ],
      ),
    );
  }

  Widget _segment(String label, String code) {
    final selected = languageCode == code;
    return GestureDetector(
      key: ValueKey<String>('landing-language-$code'),
      onTap: selected ? null : () => onSelected(code),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 37.5,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? LandingColors.segmentSelected : Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          label,
          style: figtree(
            size: 12,
            weight: FontWeight.w600,
            color: selected ? LandingColors.text : LandingColors.placeholder,
          ),
        ),
      ),
    );
  }
}

// ── guest pill ───────────────────────────────────────────────────────────────

/// `btn-guest` `631:17` — the burgundy "Continue as Guest" pill that
/// `Login Screen New ` (`630:116`) adds to the top-left of the header band,
/// opposite the EN | TR switcher.
///
/// **Deliberately inert.** The frame is a design only: the user asked for the
/// pill to be drawn and for pressing it to lead nowhere, so there is no guest
/// session, no route and no tap feedback behind it. [onTap] is the seam to wire
/// it up later; while it is null the pill does not react to touch at all.
///
/// The frame places the pill 6pt below the switcher, which reads as a stray
/// nudge rather than intent — it is a loose sibling of `language-switcher`
/// rather than a child — so the two are centred on one row here.
class LandingGuestPill extends StatelessWidget {
  const LandingGuestPill({super.key, required this.label, this.onTap});

  final String label;

  /// Left null by the login screen: the design is not connected to anything.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          color: LandingColors.accent,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: Text(
          label,
          maxLines: 1,
          // The pill sizes to its label; Turkish is the longer string and
          // still clears the switcher. The clamp is only so a very large
          // system text scale trims rather than overflowing the row.
          overflow: TextOverflow.ellipsis,
          style: figtree(
            size: 13,
            weight: FontWeight.w600,
            height: 16 / 13,
            // The frame tracks the label at 0; without this the pill inherits
            // Material's 0.25 on `bodyMedium` and widens by 4pt.
            letterSpacing: 0,
            // On burgundy in both themes, exactly like the Log In label.
            color: const Color(0xFFFAFAFA),
          ),
        ),
      ),
    );
  }
}

// ── fields ───────────────────────────────────────────────────────────────────

/// `input-username` / `input-password` `495:21` / `495:24` — a transparent
/// 45pt capsule with a quiet neutral hairline. Focus and typing deliberately do
/// not add an accent fill, border, cursor, or selection handle.
class LandingField extends StatelessWidget {
  const LandingField({
    super.key,
    required this.controller,
    required this.hint,
    this.semanticLabel,
    this.obscureText = false,
    this.suffixText,
    this.trailing,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final String? semanticLabel;
  final bool obscureText;

  /// `@ku.edu.tr`. The frame's placeholder promises "Username, email, or phone
  /// number"; this app authenticates one way only — a campus address — so the
  /// domain stays pinned to the field and is never typed.
  final String? suffixText;

  final Widget? trailing;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: ValueKey<String>(
        'landing-field-${obscureText ? 'password' : 'email'}',
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: LandingColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  cursorColor: LandingColors.text,
                  selectionColor: LandingColors.placeholder.withValues(
                    alpha: 0.22,
                  ),
                  selectionHandleColor: LandingColors.placeholder,
                ),
              ),
              child: Semantics(
                label: semanticLabel,
                child: TextField(
                  controller: controller,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  cursorColor: LandingColors.text,
                  cursorErrorColor: LandingColors.text,
                  style: figtree(
                    size: 14,
                    weight: FontWeight.w500,
                    color: LandingColors.text,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    hintText: controller.text.isEmpty ? hint : null,
                    hintStyle: figtree(
                      size: 14,
                      weight: FontWeight.w400,
                      color: LandingColors.placeholder,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (suffixText != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                suffixText!,
                style: figtree(
                  size: 13,
                  weight: FontWeight.w500,
                  color: LandingColors.placeholder,
                ),
              ),
            ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

// ── buttons ──────────────────────────────────────────────────────────────────

/// `btn-login` `495:27` — the gradient CTA, with the frame's soft accent bloom
/// under it. Disabled it flattens to the field surface so the screen still
/// reads as "type something first".
class LandingPrimaryButton extends StatefulWidget {
  const LandingPrimaryButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.submitting,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool submitting;
  final VoidCallback onTap;

  @override
  State<LandingPrimaryButton> createState() => _LandingPrimaryButtonState();
}

class _LandingPrimaryButtonState extends State<LandingPrimaryButton> {
  bool _pressed = false;

  void _release() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled || widget.submitting;
    final interactive = widget.enabled && !widget.submitting;

    return GestureDetector(
      onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
      onTapUp: interactive ? (_) => _release() : null,
      onTapCancel: interactive ? _release : null,
      onTap: interactive
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 51,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            gradient: active ? LandingColors.primaryGradient : null,
            color: active ? null : LandingColors.field,
            border: Border.all(
              color: active ? Colors.transparent : LandingColors.border,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: LandingColors.accent.withValues(alpha: 0.28),
                      blurRadius: _pressed ? 10 : 20,
                      offset: Offset(0, _pressed ? 3 : 8),
                    ),
                  ]
                : null,
          ),
          child: widget.submitting
              ? const SizedBox(
                  key: ValueKey('landing-progress'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  widget.label,
                  style: figtree(
                    size: 16,
                    weight: FontWeight.w700,
                    color: active
                        ? const Color(0xFFFAFAFA)
                        : LandingColors.placeholder,
                  ),
                ),
        ),
      ),
    );
  }
}

/// `btn-signup` `495:34` — outlined, filled with the page in dark and with the
/// card in light, exactly as the two frames sample.
class LandingSecondaryButton extends StatelessWidget {
  const LandingSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 45,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: themeService.isDark
              ? LandingColors.background
              : LandingColors.field,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: LandingColors.border),
        ),
        child: Text(
          label,
          style: figtree(
            size: 14,
            weight: FontWeight.w700,
            color: LandingColors.text,
          ),
        ),
      ),
    );
  }
}

/// `divider` `495:30` — a rule either side of a small "OR".
class LandingOrDivider extends StatelessWidget {
  const LandingOrDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: LandingColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: figtree(
              size: 12,
              weight: FontWeight.w500,
              color: LandingColors.subtle,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: LandingColors.border)),
      ],
    );
  }
}

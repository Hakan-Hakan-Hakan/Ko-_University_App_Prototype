import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_bootstrap.dart';
import '../services/auth_service.dart';
import '../services/app_strings.dart';
import '../services/locale_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_motion.dart';
import '../widgets/clubup_design.dart';
import '../widgets/landing_design.dart';
import 'club_admin_auth_screen.dart';
import 'forgot_password_screen.dart';
import 'platform_admin_auth_screen.dart';

/// `login-screen-light` / `login-screen` (Figma `495:5` / `485:5`) — the FİRST
/// LANDİNG PAGE section, and the app's root.
///
/// Stripped to the frame: the KU crest, the "KOÇ UNIVERSITY" line and the
/// "Sign in to continue" subtitle are gone, the field labels and leading icons
/// with them. What is left is the wordmark, two placeholder-only inputs, the
/// gradient Log In, Forgot password?, an OR rule, Sign Up, and the quiet
/// "Club Admin Portal" footer — which still hides the five-tap platform-admin
/// entry point.
///
/// The auth itself is untouched: students type the local part of a campus
/// address and a 6-digit PIN, and "@ku.edu.tr" stays pinned to the field.
class LoginScreen extends StatefulWidget {
  final VoidCallback onLogin;
  final VoidCallback onSignUp;
  final VoidCallback onAdminLogin;

  /// Opens the guest joyride. Left null by hosts that have no session to give
  /// (the sign-up flow reuses this screen), in which case the guest pill stays
  /// inert exactly as it was drawn.
  final VoidCallback? onGuestLogin;
  final VoidCallback? onBack;
  final String initialEmail;
  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onSignUp,
    required this.onAdminLogin,
    this.onGuestLogin,
    this.onBack,
    this.initialEmail = '',
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _emailController;
  late final AnimationController _entranceController;
  late final Animation<double> _brandEntrance;
  late final Animation<double> _formEntrance;
  late final Animation<double> _actionsEntrance;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _error;
  int _errorShakeTrigger = 0;
  bool _entranceConfigured = false;
  double _languageContentOpacity = 1;
  bool _isSwitchingLanguage = false;
  int _clubAdminTapCount = 0;
  Timer? _clubAdminTapTimer;

  static const _clubAdminTapWindow = Duration(milliseconds: 700);

  /// The campus-email field holds only the local part; "@ku.edu.tr" is a fixed
  /// suffix, so strip any domain off an incoming value (e.g. a pre-filled email
  /// after sign-up).
  static String _localPart(String email) {
    final at = email.indexOf('@');
    return at < 0 ? email : email.substring(0, at);
  }

  void _showError(String message) {
    setState(() {
      _error = message;
      _errorShakeTrigger++;
    });
  }

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: _localPart(widget.initialEmail),
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _brandEntrance = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
    );
    _formEntrance = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.18, 0.78, curve: Curves.easeOutCubic),
    );
    _actionsEntrance = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.42, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceConfigured) return;
    _entranceConfigured = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _entranceController.value = 1;
    } else {
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _clubAdminTapTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isSubmitting) return;
    final localPart = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (localPart.isEmpty || password.isEmpty) {
      _showError(AppLocalizations.of(context)!.enterEmailAndPassword);
      return;
    }
    // Users type only the local part (e.g. "htuncay23"); the "@ku.edu.tr"
    // domain is appended automatically. Lower-cased so any casing logs in.
    final email = '${localPart.toLowerCase()}@ku.edu.tr';
    if (!authService.isValidStudentPassword(password)) {
      _showError(AppLocalizations.of(context)!.studentPasswordMustBe6Digits);
      return;
    }
    setState(() {
      _error = null;
      _isSubmitting = true;
    });
    // Post-login screens read Hive boxes that open in the background after
    // first paint; by the time credentials are typed this is a no-op.
    await appBootstrap.ready;
    final success = await authService.loginStudent(email, password);
    if (!mounted) return;
    if (success) {
      widget.onLogin();
    } else {
      setState(() {
        _isSubmitting = false;
        _error = authService.lastLoginFailure == AuthLoginFailure.banned
            ? S.bannedFromApp
            : AppLocalizations.of(context)!.incorrectEmailOrPassword;
        _errorShakeTrigger++;
      });
    }
  }

  Future<void> _openForgotPassword() async {
    final resetEmail = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
    if (resetEmail != null && resetEmail.isNotEmpty) {
      _emailController.text = resetEmail;
      _passwordController.clear();
      setState(() => _error = null);
    }
  }

  void _openClubAdmin() {
    Navigator.of(context).push(
      _fadeSlideRoute(
        ClubAdminAuthScreen(
          onAdminLogin: () {
            Navigator.of(context).pop();
            widget.onAdminLogin();
          },
        ),
      ),
    );
  }

  void _openPlatformAdmin() {
    Navigator.of(context).push(
      _fadeSlideRoute(
        PlatformAdminAuthScreen(
          onAdminLogin: () {
            Navigator.of(context).pop();
            widget.onAdminLogin();
          },
        ),
      ),
    );
  }

  void _handleClubAdminEntryTap() {
    _clubAdminTapCount++;
    _clubAdminTapTimer?.cancel();

    if (_clubAdminTapCount >= 5) {
      _clubAdminTapCount = 0;
      _clubAdminTapTimer = null;
      HapticFeedback.selectionClick();
      _openPlatformAdmin();
      return;
    }

    // Wait briefly before treating the gesture as a normal club-admin tap so
    // five quick taps can reveal the separate platform-admin entry point.
    _clubAdminTapTimer = Timer(_clubAdminTapWindow, () {
      if (!mounted) return;
      _clubAdminTapCount = 0;
      _clubAdminTapTimer = null;
      _openClubAdmin();
    });
  }

  Future<void> _switchLanguage(String code) async {
    if (_isSwitchingLanguage || code == localeService.languageCode) return;
    _isSwitchingLanguage = true;
    setState(() => _languageContentOpacity = 0);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    await localeService.setLanguage(code);
    if (!mounted) return;
    setState(() => _languageContentOpacity = 1);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    _isSwitchingLanguage = false;
  }

  Widget _languageTransition({required Widget child}) {
    return AnimatedOpacity(
      opacity: _languageContentOpacity,
      duration: Duration(
        milliseconds: _languageContentOpacity == 0 ? 140 : 260,
      ),
      curve: _languageContentOpacity == 0
          ? Curves.easeInCubic
          : Curves.easeOutCubic,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: LandingColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── language-switcher + btn-guest ────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 24, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // The pill is loose-`Flexible` so an outsized system
                          // text scale trims its label instead of overflowing
                          // the row; at every normal scale it takes its own
                          // width and `spaceBetween` pushes the switcher right.
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.onBack != null)
                                  BackButton(
                                    color: LandingColors.text,
                                    onPressed: widget.onBack,
                                  ),
                                // `btn-guest` sits 24 from the page edge; the
                                // row is inset 8 to leave room for the back
                                // button, so the pill makes up the other 16
                                // when there is none.
                                Flexible(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: widget.onBack == null ? 16 : 0,
                                    ),
                                    child: _languageTransition(
                                      child: LandingGuestPill(
                                        key: const ValueKey<String>(
                                          'landing-guest-login',
                                        ),
                                        label: S.landingGuestLogin,
                                        onTap: widget.onGuestLogin,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          LandingLanguageToggle(
                            languageCode: localeService.languageCode,
                            onSelected: _switchLanguage,
                          ),
                        ],
                      ),
                    ),

                    // `spacer-top` and the spacer under `btn-signup` are the
                    // same height in the frame: the block is centred, and the
                    // footer is pinned to the bottom.
                    const Spacer(),

                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kLandingPagePadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── brand-header ─────────────────────────────────
                          _languageTransition(
                            child: _MotionEntrance(
                              animation: _brandEntrance,
                              begin: const Offset(0, -0.035),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Club',
                                      style: figtree(
                                        size: 32,
                                        weight: FontWeight.w800,
                                        color: LandingColors.accent,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Up',
                                      style: figtree(
                                        size: 32,
                                        weight: FontWeight.w800,
                                        color: LandingColors.text,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ],
                                ),
                                key: const ValueKey<String>(
                                  'landing-clubup-wordmark',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── fields + cta-block ───────────────────────────
                          _languageTransition(
                            child: _MotionEntrance(
                              animation: _formEntrance,
                              begin: const Offset(0, 0.045),
                              child: ShakeOnChange(
                                trigger: _errorShakeTrigger,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LandingField(
                                      controller: _emailController,
                                      hint: l10n.campusEmailLabel,
                                      semanticLabel: l10n.campusEmailLabel,
                                      suffixText: '@ku.edu.tr',
                                      keyboardType: TextInputType.text,
                                      inputFormatters: [_NoDomainFormatter()],
                                      onChanged: (_) =>
                                          setState(() => _error = null),
                                      onSubmitted: (_) => _handleLogin(),
                                    ),
                                    const SizedBox(height: 16),
                                    LandingField(
                                      controller: _passwordController,
                                      hint: l10n.passwordFieldLabel,
                                      obscureText: _obscurePassword,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6),
                                      ],
                                      onChanged: (_) =>
                                          setState(() => _error = null),
                                      onSubmitted: (_) => _handleLogin(),
                                      // Not in the frame: a 6-digit PIN typed
                                      // blind is easy to fat-finger, and there
                                      // is no other way to check it.
                                      trailing: GestureDetector(
                                        onTap: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                        child: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 18,
                                          color: LandingColors.placeholder,
                                        ),
                                      ),
                                    ),

                                    // The frame has no failure state; the
                                    // inline error is kept from the screen this
                                    // replaces.
                                    if (_error != null) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.error_outline_rounded,
                                            size: 15,
                                            color: LandingColors.accentText,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _error!,
                                              style: figtree(
                                                size: 12.5,
                                                weight: FontWeight.w600,
                                                color: LandingColors.accentText,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          _languageTransition(
                            child: _MotionEntrance(
                              animation: _actionsEntrance,
                              begin: const Offset(0, 0.06),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // The frame draws the CTA on its gradient in
                                  // every state, so it is never greyed out —
                                  // an empty submit falls through to the same
                                  // inline error the old screen showed.
                                  LandingPrimaryButton(
                                    label: l10n.logIn,
                                    enabled: !_isSubmitting,
                                    submitting: _isSubmitting,
                                    onTap: _handleLogin,
                                  ),
                                  const SizedBox(height: 14),
                                  GestureDetector(
                                    onTap: _openForgotPassword,
                                    behavior: HitTestBehavior.opaque,
                                    child: Text(
                                      l10n.forgotPassword,
                                      textAlign: TextAlign.center,
                                      style: figtree(
                                        size: 14,
                                        weight: FontWeight.w600,
                                        color: LandingColors.accentText,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  LandingOrDivider(label: S.landingOr),
                                  const SizedBox(height: 24),
                                  LandingSecondaryButton(
                                    label: l10n.signUp,
                                    onTap: widget.onSignUp,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // ── footer ───────────────────────────────────────────
                    // Five quick taps still reveal the platform-admin entry;
                    // one tap opens the club portal.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        kLandingPagePadding,
                        0,
                        kLandingPagePadding,
                        12,
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            key: const ValueKey<String>(
                              'club-admin-sign-in-trigger',
                            ),
                            behavior: HitTestBehavior.opaque,
                            onTap: _handleClubAdminEntryTap,
                            child: Text(
                              S.landingClubAdminPortal,
                              textAlign: TextAlign.center,
                              style:
                                  figtree(
                                    size: 11,
                                    weight: FontWeight.w500,
                                    color: LandingColors.footerLink,
                                  ).copyWith(
                                    decoration: TextDecoration.underline,
                                    decorationColor: LandingColors.footerLink,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(height: 1, color: LandingColors.border),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Coordinated entrance motion for the screen's visual hierarchy ───────────
class _MotionEntrance extends StatelessWidget {
  final Animation<double> animation;
  final Offset begin;
  final Widget child;

  const _MotionEntrance({
    required this.animation,
    required this.begin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: begin,
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

// ─── Email local-part formatter: drop anything from "@" onward ─────────────────
class _NoDomainFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final at = newValue.text.indexOf('@');
    if (at < 0) return newValue;
    final text = newValue.text.substring(0, at);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ─── Shared fade+slide route (matches the old auth-choice transition) ──────────
Route _fadeSlideRoute(Widget page) => PageRouteBuilder(
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: slide, child: child),
    );
  },
  transitionDuration: const Duration(milliseconds: 320),
);

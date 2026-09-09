import 'package:shared_preferences/shared_preferences.dart';
import 'guest_session.dart';

/// Tracks the two independent first-run milestones on this installation:
/// whether the intro was viewed and whether an authenticated state was reached.
class OnboardingIntroService {
  static const _seenPreferenceKey = 'has_seen_onboarding_intro_v1';
  static const _authenticatedPreferenceKey =
      'has_completed_onboarding_intro_v2';

  bool _seen = false;
  bool _completed = false;

  bool get hasSeenOnceOnDevice => _seen;
  bool get hasCompletedOnceOnDevice => _completed;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _completed = preferences.getBool(_authenticatedPreferenceKey) ?? false;
    // Anyone who authenticated under the old single-flag behavior has
    // necessarily already passed the intro, so migrate them without replaying
    // it after this update.
    _seen = preferences.getBool(_seenPreferenceKey) ?? _completed;
  }

  Future<void> markSeenOnDevice() async {
    if (guestSession.isActive) return;
    if (_seen) return;
    _seen = true;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_seenPreferenceKey, true);
  }

  Future<void> markCompletedOnDevice() async {
    if (guestSession.isActive) return;
    if (_completed && _seen) return;
    _completed = true;
    _seen = true;
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setBool(_authenticatedPreferenceKey, true),
      preferences.setBool(_seenPreferenceKey, true),
    ]);
  }
}

final onboardingIntroService = OnboardingIntroService();

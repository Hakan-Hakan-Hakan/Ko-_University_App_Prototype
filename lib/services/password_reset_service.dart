import 'package:flutter/widgets.dart' show Locale;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import 'locale_service.dart';
import 'rate_limit_error.dart';
import 'supabase_config.dart';
import 'guest_session.dart';

class PasswordResetResult {
  final bool success;
  final String? error;
  final String? capability;

  const PasswordResetResult.success({this.capability})
    : success = true,
      error = null;
  const PasswordResetResult.failure(this.error)
    : success = false,
      capability = null;
}

class PasswordResetService {
  // No BuildContext is available this deep in the service layer; these two
  // fallbacks never come from the server, so they're resolved here via the
  // current locale rather than pushed up to a caller that may not exist yet.
  AppLocalizations get _l10n =>
      lookupAppLocalizations(Locale(localeService.languageCode));

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  Future<PasswordResetResult> sendCode(String email) {
    return _invoke('send-password-reset-code-v2', {'email': email});
  }

  Future<PasswordResetResult> verifyCode({
    required String email,
    required String code,
  }) {
    return _invoke('verify-password-reset-code-v2', {
      'email': email,
      'code': code,
    });
  }

  Future<PasswordResetResult> updatePassword({
    required String email,
    required String password,
    required String capability,
  }) {
    return _invoke('complete-password-reset-v2', {
      'email': email,
      'password': password,
      'capability': capability,
    });
  }

  Future<PasswordResetResult> _invoke(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    final client = _client;
    if (client == null) {
      return PasswordResetResult.failure(_l10n.supabaseNotConfigured);
    }

    try {
      final response = await client.functions.invoke(functionName, body: body);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        final limited = RateLimitInfo.from(data);
        return PasswordResetResult.failure(
          limited?.displayMessage ?? data['error'].toString(),
        );
      }
      final capability = data is Map && data['capability'] is String
          ? data['capability'] as String
          : null;
      return PasswordResetResult.success(capability: capability);
    } on FunctionException catch (error) {
      final limited = RateLimitInfo.from(error);
      if (limited != null) {
        return PasswordResetResult.failure(limited.displayMessage);
      }
      final details = error.details;
      if (details is Map && details['error'] != null) {
        return PasswordResetResult.failure(details['error'].toString());
      }
      return PasswordResetResult.failure(
        error.reasonPhrase ?? _l10n.passwordResetRequestFailed,
      );
    } catch (_) {
      return PasswordResetResult.failure(_l10n.couldNotReachResetServer);
    }
  }
}

final passwordResetService = PasswordResetService();

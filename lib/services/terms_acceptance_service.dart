import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'guest_session.dart';

enum TermsAcceptanceStatus {
  signedOut,
  checking,
  acceptanceRequired,
  accepted,
  error,
}

@immutable
class TermsAcceptanceRecord {
  const TermsAcceptanceRecord({
    required this.version,
    required this.acceptedAt,
  });

  final String version;
  final DateTime acceptedAt;

  factory TermsAcceptanceRecord.fromRow(Map<String, dynamic> row) {
    final version = row['terms_version']?.toString().trim() ?? '';
    final acceptedAt = DateTime.tryParse(row['accepted_at']?.toString() ?? '');
    if (version.isEmpty || acceptedAt == null) {
      throw const FormatException('Invalid Terms acceptance record.');
    }
    return TermsAcceptanceRecord(
      version: version,
      acceptedAt: acceptedAt.toUtc(),
    );
  }
}

typedef TermsAcceptanceRowLoader =
    Future<TermsAcceptanceRecord?> Function(String userId);
typedef TermsAcceptanceRecorder =
    Future<TermsAcceptanceRecord> Function(String userId, String version);

/// Account-scoped, backend-authoritative Terms acceptance state.
///
/// [currentVersion] is the only client-side value that changes when a new
/// Terms document is published. Authenticated sessions remain closed until a
/// matching row has been read from, or successfully written to, Supabase.
class TermsAcceptanceService extends ChangeNotifier {
  TermsAcceptanceService({
    SupabaseClient? Function()? clientProvider,
    String? Function()? userIdProvider,
    TermsAcceptanceRowLoader? rowLoader,
    TermsAcceptanceRecorder? recorder,
    Duration requestTimeout = const Duration(seconds: 5),
  }) : _clientProvider = clientProvider,
       _userIdProvider = userIdProvider,
       _rowLoader = rowLoader,
       _recorder = recorder,
       _requestTimeout = requestTimeout;

  static const currentVersion = '2026-07-18';

  final SupabaseClient? Function()? _clientProvider;
  final String? Function()? _userIdProvider;
  final TermsAcceptanceRowLoader? _rowLoader;
  final TermsAcceptanceRecorder? _recorder;
  final Duration _requestTimeout;

  TermsAcceptanceStatus _status = TermsAcceptanceStatus.signedOut;
  String? _loadedUserId;
  TermsAcceptanceRecord? _latestAcceptance;
  Object? _lastError;
  int _requestGeneration = 0;

  TermsAcceptanceStatus get status => _status;
  TermsAcceptanceRecord? get latestAcceptance => _latestAcceptance;
  String? get acceptedTermsVersion => _latestAcceptance?.version;
  DateTime? get termsAcceptedAt => _latestAcceptance?.acceptedAt;
  Object? get lastError => _lastError;

  bool get hasAuthenticatedUser => _currentUserId != null;

  bool get isLoadedForCurrentUser {
    final userId = _currentUserId;
    return userId != null && _loadedUserId == userId;
  }

  bool get hasAcceptedCurrentTerms {
    final userId = _currentUserId;
    return userId != null &&
        _loadedUserId == userId &&
        _status == TermsAcceptanceStatus.accepted &&
        _latestAcceptance?.version == currentVersion;
  }

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (_clientProvider != null) return _clientProvider();
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? get _currentUserId {
    final provided = _userIdProvider?.call();
    if (provided != null && provided.isNotEmpty) return provided;
    return _client?.auth.currentUser?.id;
  }

  /// Resets process state. Acceptance is deliberately never restored from
  /// device preferences; the account row is the sole source of truth.
  Future<void> initialize() async => clear();

  /// Loads the most recently accepted Terms version for the signed-in account.
  ///
  /// Errors fail closed: the caller remains gated and can retry the check or
  /// explicitly accept the current version.
  Future<void> loadForCurrentUser() async {
    final userId = _currentUserId;
    final generation = ++_requestGeneration;
    if (userId == null) {
      clear();
      return;
    }

    _status = TermsAcceptanceStatus.checking;
    _loadedUserId = userId;
    _latestAcceptance = null;
    _lastError = null;
    notifyListeners();

    try {
      final record =
          await (_rowLoader != null
                  ? _rowLoader(userId)
                  : _loadLatestSupabaseRecord(userId))
              .timeout(_requestTimeout);
      if (!_isCurrentRequest(userId, generation)) return;

      _latestAcceptance = record;
      _status = record?.version == currentVersion
          ? TermsAcceptanceStatus.accepted
          : TermsAcceptanceStatus.acceptanceRequired;
      notifyListeners();
    } catch (error) {
      if (!_isCurrentRequest(userId, generation)) return;
      _lastError = error;
      _status = TermsAcceptanceStatus.error;
      notifyListeners();
    }
  }

  /// Records the current version and grants access only after Supabase returns
  /// the server-generated acceptance timestamp.
  Future<void> acceptCurrentTerms() async {
    final userId = _currentUserId;
    if (userId == null) {
      throw StateError('An authenticated user is required to accept Terms.');
    }

    final generation = ++_requestGeneration;
    _loadedUserId = userId;
    _lastError = null;

    try {
      final record =
          await (_recorder != null
                  ? _recorder(userId, currentVersion)
                  : _recordSupabaseAcceptance(userId))
              .timeout(_requestTimeout);
      if (!_isCurrentRequest(userId, generation)) {
        throw StateError('The authenticated account changed while saving.');
      }
      if (record.version != currentVersion) {
        throw StateError('Supabase did not confirm the current Terms version.');
      }

      _latestAcceptance = record;
      _status = TermsAcceptanceStatus.accepted;
      notifyListeners();
    } catch (error) {
      if (_isCurrentRequest(userId, generation)) {
        _lastError = error;
        _status = TermsAcceptanceStatus.error;
        notifyListeners();
      }
      rethrow;
    }
  }

  void clear() {
    _requestGeneration++;
    final changed =
        _status != TermsAcceptanceStatus.signedOut ||
        _loadedUserId != null ||
        _latestAcceptance != null ||
        _lastError != null;
    _status = TermsAcceptanceStatus.signedOut;
    _loadedUserId = null;
    _latestAcceptance = null;
    _lastError = null;
    if (changed) notifyListeners();
  }

  bool _isCurrentRequest(String userId, int generation) {
    return generation == _requestGeneration && _currentUserId == userId;
  }

  Future<TermsAcceptanceRecord?> _loadLatestSupabaseRecord(
    String userId,
  ) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is required to verify Terms acceptance.');
    }

    final row = await client
        .from('terms_acceptances')
        .select('terms_version, accepted_at')
        .eq('user_id', userId)
        .order('accepted_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return TermsAcceptanceRecord.fromRow(Map<String, dynamic>.from(row));
  }

  Future<TermsAcceptanceRecord> _recordSupabaseAcceptance(String userId) async {
    final client = _client;
    if (client == null || client.auth.currentUser?.id != userId) {
      throw StateError('An authenticated user is required to accept Terms.');
    }

    final result = await client.rpc(
      'record_terms_acceptance',
      params: {'p_terms_version': currentVersion},
    );
    final acceptedAt = DateTime.tryParse(result?.toString() ?? '');
    if (acceptedAt == null) {
      throw StateError('Supabase did not confirm Terms acceptance.');
    }
    return TermsAcceptanceRecord(
      version: currentVersion,
      acceptedAt: acceptedAt.toUtc(),
    );
  }
}

final termsAcceptanceService = TermsAcceptanceService();

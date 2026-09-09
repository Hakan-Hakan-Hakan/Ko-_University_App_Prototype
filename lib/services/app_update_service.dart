import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'guest_session.dart';

typedef AppUpdateConfigRowLoader = Future<Map<String, dynamic>?> Function();
typedef InstalledAppInfoLoader = Future<InstalledAppInfo?> Function();

@immutable
class InstalledAppInfo {
  const InstalledAppInfo({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;
}

@immutable
class AppUpdateConfig {
  const AppUpdateConfig({
    required this.androidMinimumBuild,
    required this.iosMinimumBuild,
    required this.androidStoreUrl,
    required this.iosStoreUrl,
  });

  const AppUpdateConfig.empty()
    : androidMinimumBuild = 0,
      iosMinimumBuild = 0,
      androidStoreUrl = '',
      iosStoreUrl = '';

  factory AppUpdateConfig.fromRow(Map<String, dynamic>? row) {
    if (row == null) return const AppUpdateConfig.empty();

    return AppUpdateConfig(
      androidMinimumBuild: _positiveInt(row['android_min_build']),
      iosMinimumBuild: _positiveInt(row['ios_min_build']),
      androidStoreUrl: _stringValue(row['android_store_url']),
      iosStoreUrl: _stringValue(row['ios_store_url']),
    );
  }

  final int androidMinimumBuild;
  final int iosMinimumBuild;
  final String androidStoreUrl;
  final String iosStoreUrl;

  int minimumBuildFor(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android => androidMinimumBuild,
      TargetPlatform.iOS => iosMinimumBuild,
      _ => 0,
    };
  }

  String storeUrlFor(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android => androidStoreUrl,
      TargetPlatform.iOS => iosStoreUrl,
      _ => '',
    };
  }

  static int _positiveInt(Object? value) {
    final parsed = value is int ? value : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : 0;
  }

  static String _stringValue(Object? value) {
    return value is String ? value.trim() : '';
  }
}

@immutable
class AppUpdateRequirement {
  const AppUpdateRequirement({
    required this.platform,
    required this.currentVersion,
    required this.currentBuild,
    required this.minimumBuild,
    required this.storeUrl,
  });

  final TargetPlatform platform;
  final String currentVersion;
  final int currentBuild;
  final int minimumBuild;
  final String storeUrl;
}

/// Checks whether the installed mobile build is below the remotely configured
/// minimum. The config is intentionally public and read-only: the minimum
/// supported build is not secret, while write access remains unavailable to
/// client roles through RLS.
class AppUpdateService {
  AppUpdateService({
    SupabaseClient? Function()? clientProvider,
    AppUpdateConfigRowLoader? configLoader,
    InstalledAppInfoLoader? installedAppInfoLoader,
    TargetPlatform? targetPlatform,
    bool? isWeb,
    Duration checkTimeout = const Duration(seconds: 5),
  }) : _clientProvider = clientProvider,
       _configLoader = configLoader,
       _installedAppInfoLoader = installedAppInfoLoader,
       _targetPlatform = targetPlatform,
       _isWeb = isWeb,
       _checkTimeout = checkTimeout;

  final SupabaseClient? Function()? _clientProvider;
  final AppUpdateConfigRowLoader? _configLoader;
  final InstalledAppInfoLoader? _installedAppInfoLoader;
  final TargetPlatform? _targetPlatform;
  final bool? _isWeb;
  final Duration _checkTimeout;

  TargetPlatform get targetPlatform => _targetPlatform ?? defaultTargetPlatform;

  bool get _supportsMandatoryUpdates {
    if (_isWeb ?? kIsWeb) return false;
    return targetPlatform == TargetPlatform.android ||
        targetPlatform == TargetPlatform.iOS;
  }

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    final clientProvider = _clientProvider;
    if (clientProvider != null) return clientProvider();
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<AppUpdateRequirement?> checkForRequiredUpdate() async {
    if (!_supportsMandatoryUpdates) return null;

    try {
      return await _check().timeout(_checkTimeout);
    } catch (_) {
      // An unavailable or unresponsive config service must not brick an
      // otherwise usable app. The next launch/resume retries the check.
      return null;
    }
  }

  Future<AppUpdateRequirement?> _check() async {
    final config = AppUpdateConfig.fromRow(await _loadConfigRow());
    final minimumBuild = config.minimumBuildFor(targetPlatform);
    if (minimumBuild <= 0) return null;

    final installed = await _loadInstalledAppInfo();
    if (installed == null || installed.buildNumber >= minimumBuild) {
      return null;
    }

    return AppUpdateRequirement(
      platform: targetPlatform,
      currentVersion: installed.version,
      currentBuild: installed.buildNumber,
      minimumBuild: minimumBuild,
      storeUrl: config.storeUrlFor(targetPlatform),
    );
  }

  Future<Map<String, dynamic>?> _loadConfigRow() async {
    final configLoader = _configLoader;
    if (configLoader != null) {
      return configLoader();
    }
    final client = _client;
    if (client == null) {
      return null;
    }

    final row = await client
        .from('app_update_config')
        .select(
          'android_min_build, ios_min_build, android_store_url, ios_store_url',
        )
        .eq('id', 'global')
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<InstalledAppInfo?> _loadInstalledAppInfo() async {
    final installedAppInfoLoader = _installedAppInfoLoader;
    if (installedAppInfoLoader != null) {
      return installedAppInfoLoader();
    }
    final info = await PackageInfo.fromPlatform();
    final buildNumber = int.tryParse(info.buildNumber);
    if (buildNumber == null) return null;
    return InstalledAppInfo(version: info.version, buildNumber: buildNumber);
  }
}

final appUpdateService = AppUpdateService();

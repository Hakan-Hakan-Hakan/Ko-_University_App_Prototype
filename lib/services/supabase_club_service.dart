import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/club.dart';
import 'lazy_content_loader.dart';
import 'people_service.dart';
import 'supabase_config.dart';
import 'guest_session.dart';

class SupabaseClubService {
  static const _logoBucket = 'club-avatars';

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    // Widget/integration tests and offline mock sessions do not always run
    // Supabase.initialize. In that case the existing local persistence path
    // remains available instead of treating the missing client as a failure.
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<String?> updateClubLogo({
    required Club club,
    required String imagePath,
  }) async {
    final client = _client;
    if (client == null || !_looksLikeUuid(club.id)) return null;

    // Immutable object names let the CDN and on-device cache retain the image
    // for a year without ever serving stale bytes after a logo replacement.
    final objectPath = 'clubs/${club.id}/${const Uuid().v4()}.jpg';

    await client.storage
        .from(_logoBucket)
        .upload(
          objectPath,
          File(imagePath),
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'image/jpeg',
            cacheControl: '31536000',
          ),
        );

    final publicUrl = client.storage.from(_logoBucket).getPublicUrl(objectPath);
    await client
        .from('clubs')
        .update({'logo_url': publicUrl})
        .eq('id', club.id);
    await _deleteStoredLogo(club.logoUrl, except: objectPath);
    lazyContentLoader.invalidateContent();
    return publicUrl;
  }

  Future<void> removeClubLogo(Club club) async {
    final client = _client;
    if (client == null || !_looksLikeUuid(club.id)) return;

    await client.from('clubs').update({'logo_url': null}).eq('id', club.id);
    await _deleteStoredLogo(club.logoUrl);
    lazyContentLoader.invalidateContent();
  }

  Future<void> updateClubName({
    required Club club,
    required String name,
  }) async {
    final client = _client;
    final value = name.trim();
    if (client == null || !_looksLikeUuid(club.id) || value.isEmpty) return;

    await client.from('clubs').update({'name': value}).eq('id', club.id);
    lazyContentLoader.invalidateContent();
  }

  Future<void> updateClubInitials({
    required Club club,
    required String initials,
  }) async {
    final client = _client;
    final value = normalizeClubInitials(initials);
    if (client == null ||
        !_looksLikeUuid(club.id) ||
        !isValidClubInitials(value)) {
      return;
    }

    final saved = await client
        .from('clubs')
        .update({'short_name': value})
        .eq('id', club.id)
        .select('short_name')
        .maybeSingle();
    if (saved == null || saved['short_name']?.toString() != value) {
      throw StateError('Club initials update did not affect the owned club.');
    }
    lazyContentLoader.invalidateContent();
  }

  Future<void> updateClubDescription({
    required Club club,
    required String description,
  }) async {
    final client = _client;
    final value = description.trim();
    if (client == null || !_looksLikeUuid(club.id) || value.isEmpty) return;

    await client.from('clubs').update({'description': value}).eq('id', club.id);
    lazyContentLoader.invalidateContent();
  }

  Future<void> setBoardMemberRole({
    required Club club,
    required String userId,
    String? title,
  }) async {
    final client = _client;
    final profileId = userId.trim();
    if (client == null ||
        !_looksLikeUuid(club.id) ||
        !_looksLikeUuid(profileId)) {
      return;
    }

    final roleTitle = title?.trim();
    await client
        .from('club_followers')
        .update({
          'role': 'board_member',
          'role_title': roleTitle == null || roleTitle.isEmpty
              ? null
              : roleTitle,
        })
        .eq('club_id', club.id)
        .eq('profile_id', profileId);
    peopleService.invalidateClubMembers(club.id);
    lazyContentLoader.invalidateContent();
  }

  Future<void> removeBoardMemberRole({
    required Club club,
    required String userId,
  }) async {
    final client = _client;
    final profileId = userId.trim();
    if (client == null ||
        !_looksLikeUuid(club.id) ||
        !_looksLikeUuid(profileId)) {
      return;
    }

    await client
        .from('club_followers')
        .update({'role': 'member', 'role_title': null})
        .eq('club_id', club.id)
        .eq('profile_id', profileId);
    peopleService.invalidateClubMembers(club.id);
    lazyContentLoader.invalidateContent();
  }

  String? publicLogoUrl(String? value) {
    final client = _client;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (_isRemoteImageValue(text) || client == null) return text;
    return client.storage.from(_logoBucket).getPublicUrl(text);
  }

  Future<void> _deleteStoredLogo(String? value, {String? except}) async {
    final client = _client;
    final objectPath = _objectPathFromLogoValue(value);
    if (client == null || objectPath == null || objectPath == except) return;

    try {
      await client.storage.from(_logoBucket).remove([objectPath]);
    } catch (_) {
      // Non-critical: the club row no longer points at this image.
    }
  }

  String? _objectPathFromLogoValue(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final bucketPrefix = '$_logoBucket/';
    if (text.startsWith(bucketPrefix)) {
      return text.substring(bucketPrefix.length);
    }
    if (!_isRemoteImageValue(text)) return text;

    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf(_logoBucket);
    if (bucketIndex < 0 || bucketIndex + 1 >= segments.length) return null;
    return segments.skip(bucketIndex + 1).map(Uri.decodeComponent).join('/');
  }

  bool _isRemoteImageValue(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}

final supabaseClubService = SupabaseClubService();

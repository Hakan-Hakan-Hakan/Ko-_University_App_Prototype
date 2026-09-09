import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'academic_year_options.dart';
import 'people_service.dart';
import 'supabase_config.dart';
import 'supabase_read_cache.dart';
import 'user_state.dart';
import 'guest_session.dart';

/// Supabase Storage object paths are stable across avatar replacements. A
/// changing query value gives Flutter's image cache and the storage CDN a new
/// identity for the new bytes while preserving the underlying public object.
String versionedAvatarUrl(String publicUrl, {String? version}) {
  final uri = Uri.parse(publicUrl);
  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'v': version ?? DateTime.now().microsecondsSinceEpoch.toString(),
        },
      )
      .toString();
}

class StudentProfileData {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? avatarUrl;
  final String? bio;
  final String? majorId;
  final String? majorName;
  final String? academicYearId;
  final String? academicYearName;
  final List<String> interestIds;
  final List<String> interestNames;
  final List<String> doubleMajorIds;
  final List<String> doubleMajorNames;
  final List<String> minorIds;
  final List<String> minorNames;

  const StudentProfileData({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.avatarUrl,
    this.bio,
    this.majorId,
    this.majorName,
    this.academicYearId,
    this.academicYearName,
    this.interestIds = const [],
    this.interestNames = const [],
    this.doubleMajorIds = const [],
    this.doubleMajorNames = const [],
    this.minorIds = const [],
    this.minorNames = const [],
  });
}

class ProfileLookupItem {
  final String id;
  final String name;

  const ProfileLookupItem({required this.id, required this.name});
}

class UpdateStudentProfileInput {
  final String userId;
  final String fullName;
  final String bio;
  final String? majorId;
  final String? academicYearId;
  final List<String> interestIds;
  final List<String> doubleMajorIds;
  final List<String> minorIds;

  const UpdateStudentProfileInput({
    required this.userId,
    required this.fullName,
    required this.bio,
    required this.majorId,
    required this.academicYearId,
    required this.interestIds,
    required this.doubleMajorIds,
    required this.minorIds,
  });
}

class StudentProfileService {
  static const _profileTtl = Duration(seconds: 30);
  static const _lookupTtl = Duration(minutes: 10);

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  Future<StudentProfileData?> fetchCurrentProfile() async {
    final userId = _client?.auth.currentUser?.id;
    if (userId == null) return null;
    return fetchProfile(userId);
  }

  /// Explicit private-account lookup for moderation. The database returns
  /// other users' emails only to the platform admin; ordinary callers can
  /// receive at most their own row.
  Future<Map<String, String>> fetchPrivateEmails(
    Iterable<String> profileIds,
  ) async {
    final client = _client;
    final ids = profileIds
        .where((id) => id.isNotEmpty)
        .toSet()
        .take(200)
        .toList();
    if (client == null || ids.isEmpty) return const {};

    final rows = await client.rpc<List<dynamic>>(
      'get_private_profile_emails',
      params: {'p_profile_ids': ids},
    );
    return {
      for (final row in rows.whereType<Map>())
        if ((row['profile_id']?.toString() ?? '').isNotEmpty &&
            (row['email']?.toString() ?? '').isNotEmpty)
          row['profile_id'].toString(): row['email'].toString(),
    };
  }

  Future<StudentProfileData?> fetchProfile(
    String userId, {
    bool force = false,
  }) async {
    final row = await fetchProfileCore(userId, force: force);
    if (row == null) return null;
    return _fetchDetails(row, force: force);
  }

  /// The single `profiles` row — the only query login has to block on.
  /// Everything else (interests, double majors, minors, lookup names) is
  /// resolved by [hydrateDetails] off the critical path.
  Future<Map<String, dynamic>?> fetchProfileCore(
    String userId, {
    bool force = false,
  }) async {
    final client = _client;
    if (client == null) return null;

    return supabaseReadCache.getOrFetch<Map<String, dynamic>?>(
      key: 'profile-core:$userId',
      ttl: _profileTtl,
      force: force,
      shouldCache: (value) => value != null,
      fetch: () async {
        final profile = await client
            .from('profiles')
            .select(
              'id, full_name, role, avatar_url, bio, major_id, academic_year_id',
            )
            .eq('id', userId)
            .maybeSingle();

        if (profile == null) return null;
        final result = Map<String, dynamic>.from(profile);
        if (userId == client.auth.currentUser?.id) {
          result['email'] = client.auth.currentUser?.email ?? '';
        }
        return result;
      },
    );
  }

  /// Applies the fields the core `profiles` row already carries (bio +
  /// avatar), so the first frame after login shows them without waiting for
  /// the detail queries.
  void applyCoreToUserState(Map<String, dynamic> row) {
    final userId = row['id'].toString();
    userState.setBio(userId, _nullableString(row['bio']) ?? '');
    final avatarUrl = _nullableString(row['avatar_url']);
    if (avatarUrl != null) {
      userState.setProfilePhotoUrl(userId, avatarUrl);
    }
  }

  /// Resolves the detail fields for an already-fetched core row and pushes
  /// them into [userState]. Never throws: every branch degrades to empty.
  Future<StudentProfileData?> hydrateDetails(
    Map<String, dynamic> coreRow, {
    bool force = false,
  }) async {
    try {
      final profile = await _fetchDetails(coreRow, force: force);
      if (profile != null) applyToUserState(profile);
      return profile;
    } catch (_) {
      return null;
    }
  }

  Future<StudentProfileData?> _fetchDetails(
    Map<String, dynamic> profile, {
    bool force = false,
  }) {
    final userId = profile['id']?.toString() ?? '';
    if (userId.isEmpty) return Future.value(null);

    return supabaseReadCache.getOrFetch<StudentProfileData?>(
      key: 'profile-details:$userId',
      ttl: _profileTtl,
      force: force,
      shouldCache: (value) => value != null,
      fetch: () => _fetchDetailsUncached(profile),
    );
  }

  Future<StudentProfileData?> _fetchDetailsUncached(
    Map<String, dynamic> profile,
  ) async {
    final client = _client;
    if (client == null) return null;

    final userId = profile['id'].toString();
    final majorId = _nullableString(profile['major_id']);
    final academicYearId = _nullableString(profile['academic_year_id']);

    // One flat parallel batch: three session-cached full-table lookups
    // (shared with PeopleService) plus the three join tables. Replaces the
    // old join-table → lookup-by-ids sequential chains.
    final results = await Future.wait<dynamic>([
      peopleService.lookupNameMap('majors'),
      peopleService.lookupNameMap('academic_years'),
      peopleService.lookupNameMap('interests'),
      _fetchJoinIds('student_interests', 'user_id', userId, 'interest_id'),
      _fetchJoinIds('profile_double_majors', 'profile_id', userId, 'major_id'),
      _fetchJoinIds('profile_minors', 'profile_id', userId, 'major_id'),
    ]);

    final majorNames = results[0] as Map<String, String>;
    final yearNames = results[1] as Map<String, String>;
    final interestNames = results[2] as Map<String, String>;
    final interests = _resolveOrdered(
      interestNames,
      results[3] as List<String>,
    );
    final doubleMajors = _resolveOrdered(
      majorNames,
      results[4] as List<String>,
    );
    final minors = _resolveOrdered(majorNames, results[5] as List<String>);

    return StudentProfileData(
      id: userId,
      email: _nullableString(profile['email']) ?? '',
      fullName: _nullableString(profile['full_name']) ?? '',
      role: _nullableString(profile['role']) ?? 'student',
      avatarUrl: _nullableString(profile['avatar_url']),
      bio: _nullableString(profile['bio']),
      majorId: majorId,
      majorName: majorId == null ? null : _nullableString(majorNames[majorId]),
      academicYearId: academicYearId,
      academicYearName: academicYearId == null
          ? null
          : _nullableString(yearNames[academicYearId]),
      interestIds: interests.map((item) => item.id).toList(),
      interestNames: interests.map((item) => item.name).toList(),
      doubleMajorIds: doubleMajors.map((item) => item.id).toList(),
      doubleMajorNames: doubleMajors.map((item) => item.name).toList(),
      minorIds: minors.map((item) => item.id).toList(),
      minorNames: minors.map((item) => item.name).toList(),
    );
  }

  void invalidateProfile(String userId) {
    if (userId.isEmpty) return;
    peopleService.invalidateProfile(userId);
    supabaseReadCache.invalidate('profile-core:$userId');
    supabaseReadCache.invalidate('profile-details:$userId');
  }

  /// The lookup maps are fetched ordered by `sort_order`, so iterating their
  /// entries in insertion order reproduces the ordering the old
  /// `_fetchLookupItemsByIds` (`.order('sort_order')`) produced.
  List<ProfileLookupItem> _resolveOrdered(
    Map<String, String> namesById,
    List<String> ids,
  ) {
    if (ids.isEmpty) return const [];
    final wanted = ids.toSet();
    return [
      for (final entry in namesById.entries)
        if (wanted.contains(entry.key) && entry.value.isNotEmpty)
          ProfileLookupItem(id: entry.key, name: entry.value),
    ];
  }

  Future<List<String>> _fetchJoinIds(
    String tableName,
    String userColumn,
    String userId,
    String targetColumn,
  ) async {
    final client = _client;
    if (client == null) return const [];

    try {
      final rows = await client
          .from(tableName)
          .select(targetColumn)
          .eq(userColumn, userId);
      return rows
          .map((row) => _nullableString(row[targetColumn]))
          .whereType<String>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<ProfileLookupItem>> fetchMajors() {
    return _fetchLookupItems('majors');
  }

  Future<List<ProfileLookupItem>> fetchAcademicYears() async {
    final years = await _fetchLookupItems('academic_years');
    return ensurePrepAcademicYear(
      years,
      nameOf: (year) => year.name,
      createPrep: () => const ProfileLookupItem(
        id: prepAcademicYearId,
        name: prepAcademicYearName,
      ),
    );
  }

  Future<List<ProfileLookupItem>> fetchInterests() {
    return _fetchLookupItems('interests');
  }

  Future<StudentProfileData?> updateProfile(
    UpdateStudentProfileInput input,
  ) async {
    final client = _client;
    if (client == null) return null;

    invalidateProfile(input.userId);

    final actorId = client.auth.currentUser?.id;
    if (actorId == null || actorId != input.userId) {
      throw StateError('Profile saves may only update the signed-in profile.');
    }
    final raw = await client.rpc<Map<String, dynamic>>(
      'update_profile_v2',
      params: {
        'p_full_name': input.fullName,
        'p_bio': input.bio,
        'p_major_id': input.majorId,
        'p_academic_year_id': input.academicYearId,
        'p_interest_ids': input.interestIds.toSet().toList(),
        'p_double_major_ids': input.doubleMajorIds.toSet().toList(),
        'p_minor_ids': input.minorIds.toSet().toList(),
      },
    );
    final profile = _profileFromV2(Map<String, dynamic>.from(raw));
    if (profile != null) applyToUserState(profile);
    return profile;
  }

  StudentProfileData? _profileFromV2(Map<String, dynamic> row) {
    final id = _nullableString(row['id']);
    if (id == null) return null;
    List<String> strings(String key) => (row[key] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return StudentProfileData(
      id: id,
      email: _nullableString(row['email']) ?? '',
      fullName: _nullableString(row['full_name']) ?? '',
      role: _nullableString(row['role']) ?? 'student',
      avatarUrl: _nullableString(row['avatar_url']),
      bio: _nullableString(row['bio']),
      majorId: _nullableString(row['major_id']),
      majorName: _nullableString(row['major_name']),
      academicYearId: _nullableString(row['academic_year_id']),
      academicYearName: _nullableString(row['academic_year_name']),
      interestIds: strings('interest_ids'),
      interestNames: strings('interest_names'),
      doubleMajorIds: strings('double_major_ids'),
      doubleMajorNames: strings('double_major_names'),
      minorIds: strings('minor_ids'),
      minorNames: strings('minor_names'),
    );
  }

  Future<StudentProfileData?> updateFullName({
    required String userId,
    required String fullName,
  }) async {
    final client = _client;
    final value = fullName.trim();
    if (client == null || userId.isEmpty || value.isEmpty) return null;

    invalidateProfile(userId);

    await client
        .from('profiles')
        .update({
          'full_name': value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId);

    final profile = await fetchProfile(userId);
    if (profile != null) applyToUserState(profile);
    return profile;
  }

  Future<String?> uploadAvatar({
    required String userId,
    required Uint8List bytes,
  }) async {
    final client = _client;
    if (client == null || userId.isEmpty) return null;

    invalidateProfile(userId);

    final path = '$userId/avatar.jpg';
    await client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
            // The public URL is versioned below, so a long browser/CDN TTL is
            // safe and avoids re-downloading unchanged avatars.
            cacheControl: '31536000',
          ),
        );

    final publicUrl = versionedAvatarUrl(
      client.storage.from('avatars').getPublicUrl(path),
    );

    await client
        .from('profiles')
        .update({
          'avatar_url': publicUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId);

    // Profile editors have already written and selected the new local file.
    // Keep it as the immediate source of truth on this device; signup (which
    // has no local entry for the new UUID) naturally falls back to this URL.
    userState.setProfilePhotoUrl(userId, publicUrl, preserveLocal: true);
    return publicUrl;
  }

  Future<void> removeAvatar(String userId) async {
    final client = _client;
    if (client == null || userId.isEmpty) return;

    invalidateProfile(userId);

    await client
        .from('profiles')
        .update({
          'avatar_url': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId);

    try {
      final objects = await client.storage.from('avatars').list(path: userId);
      final paths = objects.map((object) => '$userId/${object.name}').toList();
      if (paths.isNotEmpty) await client.storage.from('avatars').remove(paths);
    } catch (_) {
      // Non-critical: the profile no longer points at the old avatar.
    }

    userState.removeProfilePhoto(userId);
  }

  Future<void> hydrateUserState(String userId) async {
    final profile = await fetchProfile(userId);
    if (profile == null) return;
    applyToUserState(profile);
  }

  void applyToUserState(StudentProfileData profile) {
    final userId = profile.id;
    userState.setBio(userId, profile.bio ?? '');
    userState.setMajor(userId, profile.majorName ?? '');
    userState.setYear(userId, profile.academicYearName ?? '');
    userState.setInterests(userId, profile.interestNames);
    userState.setDoubleMajors(userId, profile.doubleMajorNames);
    userState.setMinors(userId, profile.minorNames);
    if (profile.avatarUrl != null) {
      userState.setProfilePhotoUrl(userId, profile.avatarUrl!);
    }
  }

  Future<List<ProfileLookupItem>> _fetchLookupItems(String tableName) async {
    final client = _client;
    if (client == null) return const [];

    return supabaseReadCache.getOrFetch<List<ProfileLookupItem>>(
      key: 'profile-lookup:$tableName',
      ttl: _lookupTtl,
      shouldCache: (value) => value.isNotEmpty,
      fetch: () async {
        try {
          final rows = await client
              .from(tableName)
              .select('id, name')
              .eq('is_active', true)
              .order('sort_order', ascending: true);

          return rows
              .map(
                (row) => ProfileLookupItem(
                  id: row['id'].toString(),
                  name: row['name'].toString(),
                ),
              )
              .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
              .toList();
        } catch (_) {
          return const [];
        }
      },
    );
  }

  String? _nullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

final studentProfileService = StudentProfileService();

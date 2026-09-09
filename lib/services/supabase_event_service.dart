import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/content_audience.dart';
import '../models/event.dart';
import 'content_audience_store.dart';
import 'lazy_content_loader.dart';
import 'original_media_bytes.dart';
import 'supabase_config.dart';
import 'guest_session.dart';

class SupabaseEventService {
  static const _imageBucket = 'event-images';

  SupabaseClient? get _client {
    // Guest mode reuses the unconfigured-backend path: with no client every
    // remote read/write in this service degrades to its existing local no-op.
    if (guestSession.isActive) return null;
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  bool get isAvailable => _client != null;

  Future<Event> createEvent(Event event) async {
    final client = _client;
    if (client == null) {
      // The local-only path: no RPC to carry the audience, so record it here
      // or the choice is lost the moment this returns.
      await _rememberAudience(event.id, event.audience);
      return event;
    }

    final eventId = _looksLikeUuid(event.id) ? event.id : const Uuid().v4();
    final uploadedImage = event.imagePath == null
        ? null
        : await _uploadImage(
            clubId: event.clubId,
            eventId: eventId,
            imagePath: event.imagePath!,
            revision: 'cover',
          );

    dynamic response;
    try {
      response = await client
          .rpc(
            'create_club_event_transactional_v2',
            params: {
              'p_event_id': eventId,
              'p_club_id': event.clubId,
              'p_title': event.title,
              'p_description': event.description,
              'p_location': event.location,
              'p_event_date': _dateOnly(event.dateTime),
              'p_starts_at': event.dateTime.toUtc().toIso8601String(),
              'p_ends_at': event.endTime.toUtc().toIso8601String(),
              'p_image_path': uploadedImage?.path,
              'p_image_url': uploadedImage?.publicUrl,
              'p_tags': event.tags,
              'p_registration_url': event.registrationUrl,
              'p_schedule': event.schedule
                  ?.map((slot) => slot.toMap())
                  .toList(),
              'p_speakers': event.speakers
                  .map((speaker) => speaker.toMap())
                  .toList(),
            },
          )
          .single();
    } catch (error, stackTrace) {
      if (uploadedImage != null) {
        await _registerAbandonedUpload(
          clubId: event.clubId,
          eventId: eventId,
          objectPath: uploadedImage.path,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final row = Map<String, dynamic>.from(response);

    final data = row;
    lazyContentLoader.invalidateContent();
    final saved = _eventFromRow(
      data,
      fallback: event,
      uploadedImage: uploadedImage,
    );
    await _rememberAudience(saved.id, saved.audience);
    return saved;
  }

  Future<Event> updateEvent(Event event, {String? previousImagePath}) async {
    final client = _client;
    if (client == null || !_looksLikeUuid(event.id)) {
      await _rememberAudience(event.id, event.audience);
      return event;
    }

    final uploadedImage = event.imagePath == null
        ? null
        : _isRemoteImageValue(event.imagePath!)
        ? null
        : await _uploadImage(
            clubId: event.clubId,
            eventId: event.id,
            imagePath: event.imagePath!,
            revision: 'replacement-${const Uuid().v4()}',
          );

    final retainedPath =
        uploadedImage?.path ??
        ((event.imagePath == null || event.imagePath!.trim().isEmpty)
            ? null
            : _objectPathFromImageValue(event.imagePath));
    final retainedUrl =
        uploadedImage?.publicUrl ??
        ((event.imagePath == null || event.imagePath!.trim().isEmpty)
            ? null
            : event.imagePath);
    dynamic raw;
    try {
      raw = await client.rpc<Map<String, dynamic>>(
        'update_club_event_transactional_v2',
        params: {
          'p_event_id': event.id,
          'p_title': event.title,
          'p_description': event.description,
          'p_location': event.location,
          'p_event_date': _dateOnly(event.dateTime),
          'p_starts_at': event.dateTime.toUtc().toIso8601String(),
          'p_ends_at': event.endTime.toUtc().toIso8601String(),
          'p_image_path': retainedPath,
          'p_image_url': retainedUrl,
          'p_tags': event.tags,
          'p_registration_url': event.registrationUrl,
          'p_schedule': event.schedule?.map((slot) => slot.toMap()).toList(),
          'p_speakers': event.speakers
              .map((speaker) => speaker.toMap())
              .toList(),
        },
      );
    } catch (error, stackTrace) {
      if (uploadedImage != null) {
        await _registerAbandonedUpload(
          clubId: event.clubId,
          eventId: event.id,
          objectPath: uploadedImage.path,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final result = Map<String, dynamic>.from(raw as Map);
    final data = Map<String, dynamic>.from(result['entity'] as Map);
    await _finishQueuedCleanup(
      cleanupId: result['cleanup_id']?.toString(),
      objectPath: result['cleanup_path']?.toString(),
    );
    lazyContentLoader.invalidateContent();
    final saved = _eventFromRow(
      data,
      fallback: event,
      uploadedImage: uploadedImage,
    );
    await _rememberAudience(saved.id, saved.audience);
    return saved;
  }

  /// Every return path of [createEvent] and [updateEvent] goes through here,
  /// including the two early returns — those *are* the local-only path the
  /// feature is exercised on, so skipping them would leave the audience
  /// recorded nowhere.
  Future<void> _rememberAudience(String id, ContentAudience audience) =>
      contentAudienceStore.setAudience(id, audience);

  Future<void> deleteEvent(Event event) async {
    final client = _client;
    if (client == null || !_looksLikeUuid(event.id)) return;

    final result = Map<String, dynamic>.from(
      await client.rpc<Map<String, dynamic>>(
        'delete_club_event_transactional_v2',
        params: {'p_event_id': event.id, 'p_club_id': event.clubId},
      ),
    );
    if (result['deleted'] != true) {
      throw StateError('Event was not deleted.');
    }
    await _finishQueuedCleanup(
      cleanupId: result['cleanup_id']?.toString(),
      objectPath: result['cleanup_path']?.toString(),
    );
    lazyContentLoader.invalidateContent();
  }

  Event _eventFromRow(
    Map<String, dynamic> data, {
    required Event fallback,
    _UploadedEventImage? uploadedImage,
  }) {
    return Event(
      id: data['id']?.toString() ?? fallback.id,
      clubId: data['club_id']?.toString() ?? fallback.clubId,
      title: data['title']?.toString() ?? fallback.title,
      description: data['description']?.toString() ?? fallback.description,
      location: data['location']?.toString() ?? fallback.location,
      dateTime: tryParseEventDateTime(data['starts_at']) ?? fallback.dateTime,
      endTime: tryParseEventDateTime(data['ends_at']) ?? fallback.endTime,
      attendeeUserIds: fallback.attendeeUserIds,
      rsvpTimestamps: fallback.rsvpTimestamps,
      imagePath:
          data['image_url']?.toString() ??
          uploadedImage?.publicUrl ??
          _publicUrlForObjectPath(data['image_path']?.toString()),
      createdByUserId:
          data['created_by_user_id']?.toString() ?? fallback.createdByUserId,
      tags: _stringList(data['tags']),
      schedule: _scheduleFromRaw(data['schedule']) ?? fallback.schedule,
      registrationUrl:
          data['registration_url']?.toString() ?? fallback.registrationUrl,
      speakers: _speakersFromRaw(data['speakers']),
      // The column does not exist yet, so the client's choice is the only
      // source. Becomes contentAudienceFromWire(data['audience']) later.
      audience: fallback.audience,
    );
  }

  Future<_UploadedEventImage> _uploadImage({
    required String clubId,
    required String eventId,
    required String imagePath,
    required String revision,
  }) async {
    final client = _client;
    if (client == null) {
      return _UploadedEventImage(path: imagePath, publicUrl: imagePath);
    }

    final bytes = await readCanonicalMediaBytes(File(imagePath));
    final objectPath = 'events/$clubId/$eventId/$revision.jpg';

    await client.storage
        .from(_imageBucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'image/jpeg',
            cacheControl: '31536000',
          ),
        );

    return _UploadedEventImage(
      path: objectPath,
      publicUrl: client.storage.from(_imageBucket).getPublicUrl(objectPath),
    );
  }

  Future<void> _registerAbandonedUpload({
    required String clubId,
    required String eventId,
    required String objectPath,
  }) async {
    try {
      await _client?.rpc(
        'register_abandoned_content_upload_v2',
        params: {
          'p_bucket_id': _imageBucket,
          'p_object_path': objectPath,
          'p_entity_type': 'event',
          'p_entity_id': eventId,
          'p_club_id': clubId,
        },
      );
    } catch (_) {}
  }

  Future<void> _finishQueuedCleanup({
    required String? cleanupId,
    required String? objectPath,
  }) async {
    final client = _client;
    if (client == null || cleanupId == null || objectPath == null) return;
    try {
      await client.storage.from(_imageBucket).remove([objectPath]);
      await client.rpc(
        'complete_storage_cleanup_v2',
        params: {'p_cleanup_id': cleanupId},
      );
    } catch (_) {
      // The DB already points at the new object/is deleted; queue retries later.
    }
  }

  String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) return raw.map((value) => value.toString()).toList();
    return const [];
  }

  List<EventSlot>? _scheduleFromRaw(dynamic raw) {
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map((slot) => EventSlot.fromMap(Map<String, dynamic>.from(slot)))
        .toList();
  }

  List<EventSpeaker> _speakersFromRaw(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (speaker) => EventSpeaker.fromMap(Map<String, dynamic>.from(speaker)),
        )
        .toList();
  }

  String? _publicUrlForObjectPath(String? imagePath) {
    final client = _client;
    final value = imagePath?.trim() ?? '';
    if (value.isEmpty) return null;
    if (_isRemoteImageValue(value) || client == null) return value;
    return client.storage.from(_imageBucket).getPublicUrl(value);
  }

  bool _isRemoteImageValue(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  String? _objectPathFromImageValue(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final bucketPrefix = '$_imageBucket/';
    if (text.startsWith(bucketPrefix)) {
      return text.substring(bucketPrefix.length);
    }
    if (!_isRemoteImageValue(text)) return text;

    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf(_imageBucket);
    if (bucketIndex < 0 || bucketIndex + 1 >= segments.length) return null;
    return segments.skip(bucketIndex + 1).map(Uri.decodeComponent).join('/');
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}

final supabaseEventService = SupabaseEventService();

class _UploadedEventImage {
  final String path;
  final String publicUrl;

  const _UploadedEventImage({required this.path, required this.publicUrl});
}

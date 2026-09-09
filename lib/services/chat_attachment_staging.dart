import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'guest_session.dart';

const chatAttachmentAbandonmentAge = Duration(days: 7);

/// Staging segment used while the guest joyride owns the session.
const String kGuestStagingAccountId = 'guest-session';

class ChatAttachmentStagingService {
  const ChatAttachmentStagingService();

  Future<Directory> _root({Directory? rootOverride}) async {
    if (rootOverride != null) return rootOverride;
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/chat_attachments');
  }

  Future<String> stage(
    String sourcePath, {
    String? sourceName,
    String? accountId,
    Directory? rootOverride,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Chat attachment does not exist', sourcePath);
    }
    final resolvedAccountId = _safeSegment(
      // Guest attachments get their own segment so leaving the joyride can
      // delete precisely them (see `clearGuestWorld`) without touching a real
      // account's staged files.
      accountId ??
          (guestSession.isActive ? kGuestStagingAccountId : null) ??
          _currentAuthId() ??
          'signed-out',
    );
    final root = await _root(rootOverride: rootOverride);
    final directory = Directory('${root.path}/$resolvedAccountId');
    await directory.create(recursive: true);
    final extension = _extension(sourceName ?? sourcePath);
    final target = File(
      '${directory.path}/chat_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await source.copy(target.path);
    return target.path;
  }

  Future<void> deleteIfStaged(String? path, {Directory? rootOverride}) async {
    final value = path?.trim() ?? '';
    if (value.isEmpty) return;
    final root = await _root(rootOverride: rootOverride);
    if (!_isWithin(root.path, value)) return;
    final file = File(value);
    if (await file.exists()) await file.delete();
  }

  Future<void> cleanupAccount(
    String accountId, {
    Directory? rootOverride,
  }) async {
    final root = await _root(rootOverride: rootOverride);
    final directory = Directory('${root.path}/${_safeSegment(accountId)}');
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<int> sweep({
    required Set<String> activePaths,
    Duration maxAge = chatAttachmentAbandonmentAge,
    DateTime? now,
    Directory? rootOverride,
  }) async {
    final root = await _root(rootOverride: rootOverride);
    if (!await root.exists()) return 0;
    final protected = activePaths
        .map(File.new)
        .map((file) => file.absolute.path)
        .toSet();
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    var deleted = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || protected.contains(entity.absolute.path)) continue;
      final modified = await entity.lastModified();
      if (modified.isAfter(cutoff)) continue;
      await entity.delete();
      deleted++;
    }
    return deleted;
  }

  String? _currentAuthId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  bool _isWithin(String root, String candidate) {
    final normalizedRoot = Directory(root).absolute.path;
    final normalizedCandidate = File(candidate).absolute.path;
    return normalizedCandidate.startsWith(
      '$normalizedRoot${Platform.pathSeparator}',
    );
  }

  String _safeSegment(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

const chatAttachmentStagingService = ChatAttachmentStagingService();

Future<String> stageChatAttachment(
  String sourcePath, {
  String? sourceName,
  String? accountId,
}) => chatAttachmentStagingService.stage(
  sourcePath,
  sourceName: sourceName,
  accountId: accountId,
);

String _extension(String value) {
  final dot = value.lastIndexOf('.');
  if (dot == -1 || dot == value.length - 1) return '.jpg';
  final extension = value.substring(dot).toLowerCase();
  return const {
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.gif',
        '.heic',
        '.heif',
        '.mp4',
        '.mov',
        '.m4v',
        '.avi',
        '.webm',
        '.mkv',
        '.3gp',
      }.contains(extension)
      ? extension
      : '.jpg';
}

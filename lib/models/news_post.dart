import 'content_audience.dart';

/// Poll attached to a post: a question with 2–4 options students vote on.
/// The option index doubles as the option id.
class PollData {
  final String question;
  final List<String> options;

  /// Supabase `polls.id` when known (attached at content load). Lets vote
  /// reads/writes skip the extra poll-id lookup query. Null for local polls
  /// composed in-app and for data persisted before this field existed.
  final String? pollId;

  const PollData({required this.question, required this.options, this.pollId});

  Map<String, dynamic> toMap() => {
    'question': question,
    'options': options,
    if (pollId != null) 'pollId': pollId,
  };

  factory PollData.fromMap(Map<String, dynamic> m) => PollData(
    question: m['question'] as String,
    options: List<String>.from(m['options'] as List),
    pollId: m['pollId'] as String?,
  );
}

class NewsPost {
  final String id;
  final String clubId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final List<String> taggedClubIds;
  final List<String> taggedUserIds;
  // null = use club gradient fallback
  // "tpl:N" = built-in template index N
  // any other string = local file path picked from gallery
  final String? imagePath;

  /// Optional attached poll.
  final PollData? poll;

  /// Club-wide announcement: gets a megaphone banner and sorts to the top of
  /// the club's feed section (distinct from per-user pinning).
  final bool isAnnouncement;

  /// Who this post is addressed to. See [ContentAudience] — three nested
  /// tiers, defaulting to [ContentAudience.everyone].
  final ContentAudience audience;

  // Legacy persisted field. Not displayed anywhere in the UI.
  final String title;

  NewsPost({
    required this.id,
    required this.clubId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.title = '',
    this.taggedClubIds = const [],
    this.taggedUserIds = const [],
    this.imagePath,
    this.poll,
    this.isAnnouncement = false,
    this.audience = ContentAudience.everyone,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'clubId': clubId,
    'authorId': authorId,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'title': title,
    'taggedClubIds': taggedClubIds,
    'taggedUserIds': taggedUserIds,
    'imagePath': imagePath,
    'poll': poll?.toMap(),
    'isAnnouncement': isAnnouncement,
    'audience': audience.wireValue,
  };

  factory NewsPost.fromMap(Map<String, dynamic> m) => NewsPost(
    id: m['id'] as String,
    clubId: m['clubId'] as String,
    authorId: m['authorId'] as String,
    content: m['content'] as String,
    createdAt: DateTime.parse(m['createdAt'] as String),
    title: m['title'] as String? ?? '',
    taggedClubIds: List<String>.from(m['taggedClubIds'] as List? ?? []),
    taggedUserIds: List<String>.from(m['taggedUserIds'] as List? ?? []),
    imagePath: m['imagePath'] as String?,
    poll: m['poll'] == null
        ? null
        : PollData.fromMap(Map<String, dynamic>.from(m['poll'] as Map)),
    isAnnouncement: m['isAnnouncement'] as bool? ?? false,
    audience: contentAudienceFromWire(m['audience']),
  );

  /// Field-wise copy.
  ///
  /// Several call sites rebuild a post by hand — the Feed v2 adapter, the poll
  /// attach pass, the create-post return — and every one of them silently drops
  /// any field it does not know about. Prefer this over a fresh [NewsPost].
  ///
  /// Note this cannot null a field back out: passing `imagePath: null` keeps the
  /// existing value rather than clearing it. Nothing needs that today.
  NewsPost copyWith({
    String? id,
    String? clubId,
    String? authorId,
    String? content,
    DateTime? createdAt,
    String? title,
    List<String>? taggedClubIds,
    List<String>? taggedUserIds,
    String? imagePath,
    PollData? poll,
    bool? isAnnouncement,
    ContentAudience? audience,
  }) => NewsPost(
    id: id ?? this.id,
    clubId: clubId ?? this.clubId,
    authorId: authorId ?? this.authorId,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    title: title ?? this.title,
    taggedClubIds: taggedClubIds ?? this.taggedClubIds,
    taggedUserIds: taggedUserIds ?? this.taggedUserIds,
    imagePath: imagePath ?? this.imagePath,
    poll: poll ?? this.poll,
    isAnnouncement: isAnnouncement ?? this.isAnnouncement,
    audience: audience ?? this.audience,
  );
}

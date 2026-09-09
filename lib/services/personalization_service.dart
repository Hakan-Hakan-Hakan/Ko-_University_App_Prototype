import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'mock_data.dart';
import 'guest_session.dart';

// ── Interest & time labels ────────────────────────────────────────────────────

const List<String> kInterests = [
  'Tech',
  'Arts',
  'Music',
  'Sports',
  'Academic',
  'Career',
  'Wellness',
  'Social Impact',
];

const List<String> kTimeSlots = ['Morning', 'Afternoon', 'Evening', 'Weekend'];

/// Canonical identity for programme names that differ only by backend/display
/// spelling, such as "Chemical & Biological" versus "Chemical and Biological".
String normalizeAcademicProgramName(String program) {
  return program
      .trim()
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'\s+'), ' ');
}

const List<String> kAcademicPrograms = [
  'Archaeology and History of Art',
  'Business Administration',
  'Chemical and Biological Engineering',
  'Chemistry',
  'Comparative Literature',
  'Computer Engineering',
  'Economics',
  'Electrical and Electronics Engineering',
  'History',
  'Industrial Engineering',
  'International Relations',
  'Law',
  'Mathematics',
  'Mechanical Engineering',
  'Media and Visual Arts',
  'Medicine',
  'Molecular Biology and Genetics',
  'Nursing',
  'Philosophy',
  'Physics',
  'Psychology',
  'Sociology',
];

/// Weekly lecture schedule for the current user (Hakan Tuncay).
/// days: 1=Mon 2=Tue 3=Wed 4=Thu 5=Fri
const List<Map<String, dynamic>> kCourseSchedule = [
  {
    'title': 'MFIN 304 · Investment Analysis',
    'room': 'CASE Z24',
    'startH': 8,
    'startM': 30,
    'endH': 9,
    'endM': 40,
    'days': [2, 4],
    'color': 0xFF7B1FA2,
  },
  {
    'title': 'INTL 380 · Comp. Political Economy',
    'room': 'SNA 157',
    'startH': 11,
    'startM': 30,
    'endH': 12,
    'endM': 40,
    'days': [1, 3],
    'color': 0xFF1565C0,
  },
  {
    'title': 'MATH 480 · Financial Mathematics',
    'room': 'CASE Z25',
    'startH': 13,
    'startM': 0,
    'endH': 14,
    'endM': 10,
    'days': [1, 3],
    'color': 0xFF2E7D32,
  },
  {
    'title': 'INTL 385 · Turkish Foreign Policy',
    'room': 'CASE B24',
    'startH': 14,
    'startM': 30,
    'endH': 15,
    'endM': 40,
    'days': [2, 4],
    'color': 0xFF283593,
  },
  {
    'title': 'HIST 300 · Hist. of Modern Turkey',
    'room': 'CASE B24',
    'startH': 16,
    'startM': 0,
    'endH': 17,
    'endM': 10,
    'days': [1, 3],
    'color': 0xFFBF360C,
  },
  {
    'title': 'UNIV 198 · AI Literacy',
    'room': 'SOS B07',
    'startH': 11,
    'startM': 30,
    'endH': 12,
    'endM': 40,
    'days': [4, 5],
    'color': 0xFF00695C,
  },
];

/// Faculty → departments map. Edit here to update the major picker.
const List<Map<String, dynamic>> kFaculties = [
  {'name': 'Engineering', 'departments': 'CS, EE, ME, IE, ChBE'},
  {'name': 'Sciences', 'departments': 'Physics, Chemistry, Math, MBG'},
  {'name': 'Business & Economics', 'departments': 'BA, Economics, IR'},
  {
    'name': 'Social Sciences & Humanities',
    'departments': 'Psychology, History, Media, Philosophy',
  },
  {'name': 'Law', 'departments': 'Hukuk Fakültesi'},
  {'name': 'Medicine', 'departments': 'Tıp Fakültesi'},
  {'name': 'Undecided', 'departments': 'Not sure yet'},
];

// ── Service ───────────────────────────────────────────────────────────────────

class PersonalizationService extends ChangeNotifier {
  static const _boxName = 'personalization';

  /// Bump this when the onboarding flow changes structurally (new steps, etc.).
  /// Any user whose stored version doesn't match will be sent through onboarding
  /// again exactly once — their interests/times/major are NOT cleared.
  static const int _onboardingVersion = 1;

  Box<dynamic>? _box;

  bool onboardingComplete = false;
  Set<String> interests = {};
  Set<String> timePrefs = {};
  String major = '';
  Set<String> hiddenIds = {};
  Set<String> remindedEventIds = {};

  Future<void> initialize() async {
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  // ── Load ────────────────────────────────────────────────────────────────────

  void load(String userId) {
    if (_box == null) return;
    // If the stored onboarding version doesn't match the current one,
    // mark onboarding as incomplete so the user sees the new flow once.
    // Their existing interests/times/major are preserved.
    final storedVersion = _box!.get('obv_$userId', defaultValue: 0) as int;
    final versionMatch = storedVersion == _onboardingVersion;

    onboardingComplete =
        versionMatch && (_box!.get('ob_$userId', defaultValue: false) as bool);
    interests = _restoreSet(_box!.get('int_$userId'));
    timePrefs = _restoreSet(_box!.get('tp_$userId'));
    major = _box!.get('major_$userId', defaultValue: '') as String;
    hiddenIds = _restoreSet(_box!.get('hid_$userId'));
    remindedEventIds = _restoreSet(_box!.get('rem_$userId'));
    notifyListeners();
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> save(String userId) async {
    if (guestSession.isActive) return;
    if (_box == null) return;
    await _box!.putAll({
      'ob_$userId': onboardingComplete,
      'obv_$userId': _onboardingVersion,
      'int_$userId': interests.toList(),
      'tp_$userId': timePrefs.toList(),
      'major_$userId': major,
      'hid_$userId': hiddenIds.toList(),
      'rem_$userId': remindedEventIds.toList(),
    });
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  Future<void> completeOnboarding(
    String userId,
    Set<String> selectedInterests,
    Set<String> selectedTimePrefs,
    String selectedMajor,
  ) async {
    onboardingComplete = true;
    interests = Set.of(selectedInterests);
    timePrefs = Set.of(selectedTimePrefs);
    major = selectedMajor;
    notifyListeners();
    await save(userId);
  }

  Future<void> hideItem(String userId, String id) async {
    hiddenIds.add(id);
    notifyListeners();
    await save(userId);
  }

  Future<void> remindEvent(String userId, String eventId) async {
    remindedEventIds.add(eventId);
    notifyListeners();
    await save(userId);
  }

  Future<void> unremindEvent(String userId, String eventId) async {
    remindedEventIds.remove(eventId);
    notifyListeners();
    await save(userId);
  }

  // ── Queries ─────────────────────────────────────────────────────────────────

  bool isHidden(String id) => hiddenIds.contains(id);
  bool isReminded(String id) => remindedEventIds.contains(id);

  /// Returns interest tags for the given club ID.
  List<String> interestsForClub(String clubId) {
    final category = clubForId(clubId)?.categoryName?.trim();
    if (category == null || category.isEmpty) return const [];
    return [category];
  }

  /// How many of the user's selected interests match a given club.
  int interestMatchCount(String clubId) =>
      interestsForClub(clubId).where(interests.contains).length;

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Set<String> _restoreSet(dynamic raw) =>
      raw != null ? Set<String>.from(raw as List) : {};
}

final personalizationService = PersonalizationService();

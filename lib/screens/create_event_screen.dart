import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/content_audience.dart';
import '../models/event.dart';
import '../services/app_strings.dart';
import '../services/content_visibility.dart';
import '../services/app_colors.dart';
import '../services/account_switcher_service.dart';
import '../services/auth_service.dart';
import '../services/club_admin_access.dart';
import '../services/club_notification_service.dart';
import '../services/content_store.dart';
import '../services/mock_data.dart';
import '../services/photo_upload_quality.dart';
import '../services/rate_limit_error.dart';
import '../services/supabase_event_service.dart';
import '../widgets/clubup_design.dart';
import '../widgets/content_audience_sheet.dart';
import '../widgets/event_wizard_design.dart';
import '../l10n/app_localizations.dart';

class CreateEventScreen extends StatefulWidget {
  final VoidCallback? onCreated;
  final SupabaseEventService? eventService;

  /// When provided, the form opens in edit mode pre-filled with this event and
  /// saves changes in place instead of creating a new event.
  final Event? existing;

  const CreateEventScreen({
    super.key,
    this.onCreated,
    this.existing,
    this.eventService,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _ScheduleEntry {
  TimeOfDay time;
  TextEditingController titleCtrl;
  TextEditingController subtitleCtrl;
  bool isHighlighted = false;

  _ScheduleEntry({
    required this.time,
    required this.titleCtrl,
    required this.subtitleCtrl,
  });

  void dispose() {
    titleCtrl.dispose();
    subtitleCtrl.dispose();
  }
}

class _SpeakerEntry {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController roleCtrl = TextEditingController();
  final TextEditingController linkedinCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    roleCtrl.dispose();
    linkedinCtrl.dispose();
  }
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final String _reservedEventId = const Uuid().v4();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  String? _imagePath;

  // Tags
  final List<String> _selectedTags = [];
  final _customTagCtrl = TextEditingController();

  // Schedule
  final List<_ScheduleEntry> _scheduleEntries = [];

  // Registration (external sign-up link)
  bool _externalReg = false;
  final _regUrlCtrl = TextEditingController();

  // Speakers (name / role / LinkedIn)
  final List<_SpeakerEntry> _speakers = [];
  bool _isPosting = false;

  // The frame's `Starts` / `Ends` cells read "Select start date" until they are
  // picked, so a new event genuinely has no dates yet.
  DateTime? _startDate;
  DateTime? _endDate;

  /// Who the event is addressed to — `everyone` unless the club narrows it.
  ContentAudience _selectedAudience = ContentAudience.everyone;

  /// Which cell the open picker sheet belongs to — that one takes the accent
  /// ring in `315:56`.
  String? _activePicker;

  // Wizard navigation
  final PageController _pageController = PageController();
  int _step = 0;
  static const int _stepCount = 4;
  bool get _isEditing => widget.existing != null;

  SupabaseEventService get _eventService =>
      widget.eventService ?? supabaseEventService;

  @override
  void initState() {
    super.initState();
    final ev = widget.existing;
    if (ev == null) return;

    _selectedAudience = audienceForEvent(ev);
    _titleController.text = ev.title;
    _descController.text = ev.description;
    _locationController.text = ev.location;
    _imagePath = ev.imagePath;
    _selectedTags.addAll(ev.tags);
    _startDate = ev.dateTime;
    _endDate = ev.endTime;

    final reg = ev.registrationUrl?.trim() ?? '';
    if (reg.isNotEmpty) {
      _externalReg = true;
      _regUrlCtrl.text = reg;
    }

    for (final slot in ev.schedule ?? const <EventSlot>[]) {
      final entry = _ScheduleEntry(
        time: TimeOfDay(hour: slot.time.hour, minute: slot.time.minute),
        titleCtrl: TextEditingController(text: slot.title),
        subtitleCtrl: TextEditingController(text: slot.subtitle ?? ''),
      );
      entry.isHighlighted = slot.isHighlighted;
      _scheduleEntries.add(entry);
    }

    for (final sp in ev.speakers) {
      final entry = _SpeakerEntry();
      entry.nameCtrl.text = sp.name;
      entry.roleCtrl.text = sp.role;
      entry.linkedinCtrl.text = sp.linkedin ?? '';
      _speakers.add(entry);
    }
  }

  // ── Wizard navigation ────────────────────────────────────────────────────

  // Whether the user may move past [step]. Required fields are validated on the
  // step that collects them so they're always satisfied before Review.
  // Step 1 now collects the dates too, so everything required lives there.
  bool _canAdvanceFrom(int step) {
    if (step != 0) return true;
    final start = _startDate;
    final end = _endDate;
    return _titleController.text.trim().isNotEmpty &&
        _locationController.text.trim().isNotEmpty &&
        start != null &&
        end != null &&
        end.isAfter(start);
  }

  // Reason shown when a Next is blocked. The frame draws no disabled button,
  // so the CTA stays solid and says what is missing instead.
  String _blockedReason(int step) {
    final l10n = AppLocalizations.of(context)!;
    if (step != 0) return l10n.completeRequiredFields;
    final start = _startDate;
    final end = _endDate;
    if (_titleController.text.trim().isEmpty ||
        _locationController.text.trim().isEmpty) {
      return l10n.addTitleLocationToContinue;
    }
    if (start == null || end == null || !end.isAfter(start)) {
      return l10n.endTimeAfterStartTime;
    }
    return l10n.completeRequiredFields;
  }

  void _goToStep(int target) {
    final clamped = target.clamp(0, _stepCount - 1);
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    if (_step >= _stepCount - 1) return;
    if (!_canAdvanceFrom(_step)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_blockedReason(_step)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    FocusScope.of(context).unfocus();
    _goToStep(_step + 1);
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    FocusScope.of(context).unfocus();
    _goToStep(_step - 1);
  }

  String? get _adminClubId {
    final linkedClub = accountSwitcherService.activeClub;
    if (linkedClub != null) return linkedClub.id;
    final admin = authService.currentAdmin;
    if (admin == null) return null;
    try {
      return clubs.firstWhere((c) => clubIsManagedByAdmin(c, admin.id)).id;
    } catch (_) {
      return null;
    }
  }

  // ── Pickers — the frames' own sheets ─────────────────────────────────────
  /// `photo-uploader` 315:32. Same picker + crop the old hero editor used.
  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final cropPhotoTitle = AppLocalizations.of(context)!.cropPhotoTitle;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      maxWidth: PhotoUploadQuality.contentMaxDimension,
      maxHeight: PhotoUploadQuality.contentMaxDimension,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: PhotoUploadQuality.jpegQuality,
      uiSettings: [
        IOSUiSettings(
          title: cropPhotoTitle,
          resetAspectRatioEnabled: true,
          rotateButtonsHidden: false,
        ),
        AndroidUiSettings(
          toolbarTitle: cropPhotoTitle,
          toolbarColor: AppColors.primaryRed,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: false,
          showCropGrid: true,
        ),
      ],
    );
    if (cropped == null || !mounted) return;
    setState(() => _imagePath = cropped.path);
  }

  DateTime _combine(DateTime date, DateTime time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  /// `select-date` 319:7.
  Future<void> _pickDate(bool isStart) async {
    final current = isStart ? _startDate : _endDate;
    setState(() => _activePicker = isStart ? 'start-date' : 'end-date');
    final picked = await showEventWizardDateSheet(
      context,
      initial: current ?? DateTime.now(),
      firstAllowed: isStart ? null : _startDate,
    );
    if (!mounted) return;
    setState(() {
      _activePicker = null;
      if (picked == null) return;
      if (isStart) {
        final base = _startDate ?? DateTime.now();
        _startDate = _combine(picked, base);
        final end = _endDate;
        if (end != null && !end.isAfter(_startDate!)) {
          _endDate = _startDate!.add(const Duration(hours: 2));
        }
      } else {
        final base = _endDate ?? _startDate?.add(const Duration(hours: 2));
        _endDate = _combine(picked, base ?? DateTime.now());
      }
    });
  }

  /// `select-start-time` / `select-end-time` 315:71.
  Future<void> _pickTime(bool isStart) async {
    final current = isStart ? _startDate : _endDate;
    final fallback = TimeOfDay.fromDateTime(
      current ?? DateTime.now().add(Duration(hours: isStart ? 1 : 3)),
    );
    setState(() => _activePicker = isStart ? 'start-time' : 'end-time');
    final picked = await showEventWizardTimeSheet(
      context,
      initial: fallback,
      title: isStart
          ? S.eventWizardSelectStartTime
          : S.eventWizardSelectEndTime,
    );
    if (!mounted) return;
    setState(() {
      _activePicker = null;
      if (picked == null) return;
      if (isStart) {
        final base = _startDate ?? DateTime.now();
        _startDate = DateTime(
          base.year,
          base.month,
          base.day,
          picked.hour,
          picked.minute,
        );
        final end = _endDate;
        if (end != null && !end.isAfter(_startDate!)) {
          _endDate = _startDate!.add(const Duration(hours: 2));
        }
      } else {
        final base = _endDate ?? _startDate ?? DateTime.now();
        _endDate = DateTime(
          base.year,
          base.month,
          base.day,
          picked.hour,
          picked.minute,
        );
      }
    });
  }

  /// The audience sheet, driven like the date and time cells so the open one
  /// takes the accent ring.
  Future<void> _pickAudience() async {
    setState(() => _activePicker = 'audience');
    final picked = await showContentAudienceSheet(
      context,
      current: _selectedAudience,
      surface: EventWizardColors.card,
      border: EventWizardColors.border,
      text: EventWizardColors.text,
      muted: EventWizardColors.muted,
      accent: EventWizardColors.accent,
    );
    if (!mounted) return;
    setState(() {
      _activePicker = null;
      if (picked != null) _selectedAudience = picked;
    });
  }

  /// `add-speaker-modal` 325:154 — replaces the three inline fields per
  /// speaker the old Details step drew.
  Future<void> _openSpeakerSheet({int? index}) async {
    final existing = index == null
        ? null
        : EventWizardSpeakerDraft(
            name: _speakers[index].nameCtrl.text,
            role: _speakers[index].roleCtrl.text,
            linkedin: _speakers[index].linkedinCtrl.text,
          );
    final draft = await showEventWizardSpeakerSheet(
      context,
      existing: existing,
    );
    if (draft == null || !mounted) return;
    setState(() {
      final entry = index == null ? _SpeakerEntry() : _speakers[index];
      entry.nameCtrl.text = draft.name;
      entry.roleCtrl.text = draft.role;
      entry.linkedinCtrl.text = draft.linkedin;
      if (index == null) _speakers.add(entry);
    });
  }

  /// `add-session` 325:485.
  Future<void> _openSessionSheet({int? index}) async {
    final existing = index == null
        ? null
        : EventWizardSessionDraft(
            title: _scheduleEntries[index].titleCtrl.text,
            speaker: _scheduleEntries[index].subtitleCtrl.text,
            start: _scheduleEntries[index].time,
          );
    final lastTime = _scheduleEntries.isEmpty
        ? TimeOfDay.fromDateTime(_startDate ?? DateTime.now())
        : _scheduleEntries.last.time;
    final nextMinutes = lastTime.hour * 60 + lastTime.minute + 30;
    final draft = await showEventWizardSessionSheet(
      context,
      existing: existing,
      defaultStart: TimeOfDay(
        hour: (nextMinutes ~/ 60) % 24,
        minute: nextMinutes % 60,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      final entry = index == null
          ? _ScheduleEntry(
              time: draft.start,
              titleCtrl: TextEditingController(),
              subtitleCtrl: TextEditingController(),
            )
          : _scheduleEntries[index];
      entry.time = draft.start;
      entry.titleCtrl.text = draft.title;
      entry.subtitleCtrl.text = draft.speaker;
      if (index == null) _scheduleEntries.add(entry);
      _scheduleEntries.sort((a, b) {
        final am = a.time.hour * 60 + a.time.minute;
        final bm = b.time.hour * 60 + b.time.minute;
        return am.compareTo(bm);
      });
    });
  }

  void _removeScheduleEntry(int idx) {
    setState(() {
      _scheduleEntries[idx].dispose();
      _scheduleEntries.removeAt(idx);
    });
  }

  void _addTag() {
    final tag = _customTagCtrl.text.trim();
    if (tag.isEmpty || _selectedTags.contains(tag)) return;
    setState(() {
      _selectedTags.add(tag);
      _customTagCtrl.clear();
    });
  }

  Future<void> _post() async {
    final clubId = widget.existing?.clubId ?? _adminClubId;
    if (clubId == null || _isPosting) return;
    // The CTA validates step 1 before the preview can be reached, so both are
    // set by the time Publish is available.
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) return;

    // Build schedule
    List<EventSlot>? schedule;
    final filledSlots = _scheduleEntries
        .where((e) => e.titleCtrl.text.trim().isNotEmpty)
        .toList();
    if (filledSlots.isNotEmpty) {
      final baseDate = start;
      schedule = filledSlots.map((e) {
        return EventSlot(
          time: DateTime(
            baseDate.year,
            baseDate.month,
            baseDate.day,
            e.time.hour,
            e.time.minute,
          ),
          title: e.titleCtrl.text.trim(),
          subtitle: e.subtitleCtrl.text.trim().isEmpty
              ? null
              : e.subtitleCtrl.text.trim(),
          isHighlighted: e.isHighlighted,
        );
      }).toList();
    }

    final speakers = _speakers
        .where((s) => s.nameCtrl.text.trim().isNotEmpty)
        .map(
          (s) => EventSpeaker(
            name: s.nameCtrl.text.trim(),
            role: s.roleCtrl.text.trim(),
            linkedin: s.linkedinCtrl.text.trim().isEmpty
                ? null
                : s.linkedinCtrl.text.trim(),
          ),
        )
        .toList();

    final regUrl = _regUrlCtrl.text.trim();

    // ── Edit mode: update the existing event in place ──────────────────────
    if (_isEditing) {
      final ev = widget.existing!;
      final updated = Event(
        id: ev.id,
        clubId: ev.clubId,
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        location: _locationController.text.trim(),
        dateTime: start,
        endTime: end,
        attendeeUserIds: ev.attendeeUserIds,
        rsvpTimestamps: ev.rsvpTimestamps,
        imagePath: _imagePath,
        createdByUserId: ev.createdByUserId,
        tags: List.from(_selectedTags),
        schedule: schedule,
        accentColorHex: ev.accentColorHex,
        registrationUrl: (_externalReg && regUrl.isNotEmpty) ? regUrl : null,
        capacity: ev.capacity,
        speakers: speakers,
        audience: _selectedAudience,
      );
      Event saved;
      try {
        saved = await _eventService.updateEvent(
          updated,
          previousImagePath: ev.imagePath,
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.couldNotSaveEventSupabase,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }

      final ok = contentStore.updateEventForCurrentAccount(saved);
      if (!mounted) return;
      if (ok) {
        widget.onCreated?.call();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.couldNotSaveChanges),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      return;
    }

    final draftEvent = Event(
      id: _reservedEventId,
      clubId: clubId,
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      location: _locationController.text.trim(),
      dateTime: start,
      endTime: end,
      attendeeUserIds: [],
      imagePath: _imagePath,
      createdByUserId: accountSwitcherService.actorId,
      tags: List.from(_selectedTags),
      schedule: schedule,
      registrationUrl: (_externalReg && regUrl.isNotEmpty) ? regUrl : null,
      speakers: speakers,
      audience: _selectedAudience,
    );

    setState(() => _isPosting = true);
    try {
      final newEvent = await _eventService.createEvent(draftEvent);
      if (!mounted) return;
      events.add(newEvent);
      unawaited(contentStore.saveEvents());
      contentStore.notifyContentChanged();
      if (!supabaseEventService.isAvailable) {
        unawaited(clubNotificationService.notifyFollowersAboutEvent(newEvent));
      }
      widget.onCreated?.call();
      Navigator.pop(context);
    } catch (error, stackTrace) {
      debugPrint('Create event failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_publishErrorMessage(error)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  String _publishErrorMessage(Object error) {
    final l10n = AppLocalizations.of(context)!;
    final limited = RateLimitInfo.from(error);
    if (limited != null) return limited.displayMessage;
    final text = error.toString();
    if (text.contains('row-level security') ||
        text.contains('permission denied') ||
        text.contains('42501')) {
      return l10n.publishErrorRlsPolicyEvent;
    }
    if (text.contains('column') ||
        text.contains('schedule') ||
        text.contains('speakers')) {
      return l10n.publishErrorMigrationEvent;
    }
    if (text.contains('event-images') || text.contains('storage')) {
      return l10n.publishErrorStorageEvent;
    }
    return l10n.publishErrorGenericEvent;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    _customTagCtrl.dispose();
    _regUrlCtrl.dispose();
    for (final e in _scheduleEntries) {
      e.dispose();
    }
    for (final s in _speakers) {
      s.dispose();
    }
    super.dispose();
  }

  // ── Build — the `wz-*` wizard ────────────────────────────────────────────
  // Three steps plus the Event Preview page. The step chip reads "N of 3"
  // across the first three; the preview carries the frame's "Preview" badge.
  static const int _previewStep = 3;

  String get _stepTitle {
    if (_step == _previewStep) return S.eventWizardPreviewTitle;
    if (_step == 1) return S.eventWizardStepTwoTitle;
    if (_step == 2) return S.eventWizardStepThreeTitle;
    return _isEditing
        ? AppLocalizations.of(context)!.editEventTitle
        : S.eventWizardStepOneTitle;
  }

  String get _stepBadge => _step == _previewStep
      ? S.eventWizardPreviewBadge
      : S.eventWizardStepOf(_step + 1, 3);

  String get _ctaLabel {
    if (_step < 2) return S.eventWizardNextStep;
    if (_step == 2) {
      // Editing does not "create" anything, and a second "Save Changes" one
      // step before the real one would read as a double commit.
      return _isEditing ? S.eventWizardPreviewBadge : S.eventWizardCreateEvent;
    }
    return _isEditing ? S.eventWizardSaveChanges : S.eventWizardPublish;
  }

  void _onPrimaryAction() {
    if (_step < _previewStep) {
      _next();
      return;
    }
    unawaited(_post());
  }

  String _dateLabel(DateTime value) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('EEE, MMM d, y', locale).format(value);
  }

  String _longDateLabel(DateTime value) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMMEEEEd(locale).format(value);
  }

  String _timeLabel(DateTime value) =>
      TimeOfDay.fromDateTime(value).format(context);

  /// The `TONIGHT · 7 PM` line on the Live Event Preview card.
  String get _whenLabel {
    final start = _startDate;
    if (start == null) return S.eventWizardSelectStartDate;
    final now = DateTime.now();
    final sameDay =
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final time = _timeLabel(start);
    if (sameDay) return '${AppLocalizations.of(context)!.today} · $time';
    final locale = Localizations.localeOf(context).toString();
    return '${DateFormat.MMMd(locale).format(start)} · $time';
  }

  List<({String title, String speaker, String time})> get _sessionRows {
    return [
      for (final entry in _scheduleEntries)
        if (entry.titleCtrl.text.trim().isNotEmpty)
          (
            title: entry.titleCtrl.text.trim(),
            speaker: entry.subtitleCtrl.text.trim(),
            time: TimeOfDay(
              hour: entry.time.hour,
              minute: entry.time.minute,
            ).format(context),
          ),
    ];
  }

  List<EventWizardSpeakerDraft> get _speakerDrafts => [
    for (final s in _speakers)
      if (s.nameCtrl.text.trim().isNotEmpty)
        EventWizardSpeakerDraft(
          name: s.nameCtrl.text.trim(),
          role: s.roleCtrl.text.trim(),
          linkedin: s.linkedinCtrl.text.trim(),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EventWizardColors.page,
      body: SafeArea(
        child: Column(
          children: [
            EventWizardTopBar(
              title: _stepTitle,
              stepLabel: _stepBadge,
              onBack: _back,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _buildDetailsStep(),
                  _buildSpeakersStep(),
                  _buildProgrammeStep(),
                  _buildPreviewStep(),
                ],
              ),
            ),
            EventWizardBottomAction(
              label: _ctaLabel,
              busy: _isPosting,
              onTap: _onPrimaryAction,
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1 of 3 — `light-details` 310:11 / `light-start-time` 315:8 ───────
  Widget _buildDetailsStep() {
    final start = _startDate;
    final end = _endDate;
    return ListView(
      key: const ValueKey('event-wizard-step-details'),
      padding: const EdgeInsets.all(kEventWizardGutter),
      children: [
        EventWizardPhotoUploader(
          imagePath: _imagePath,
          onTap: () => unawaited(_pickCover()),
        ),
        const SizedBox(height: 16),
        EventWizardTextField(
          fieldKey: const ValueKey('event-wizard-title-field'),
          controller: _titleController,
          label: S.eventWizardTitleLabel,
          hint: S.eventWizardTitleHint,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        EventWizardTextField(
          fieldKey: const ValueKey('event-wizard-location-field'),
          controller: _locationController,
          label: S.eventWizardLocationLabel,
          hint: S.eventWizardLocationHint,
          icon: Icons.place_outlined,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        // The newest step-1 frames (315:8, 319:7) drop the description, but the
        // Event Preview still prints "About this Event" — so it stays.
        EventWizardTextField(
          fieldKey: const ValueKey('event-wizard-description-field'),
          controller: _descController,
          label: S.eventWizardDescriptionLabel,
          hint: S.eventWizardDescriptionHint,
          minLines: 3,
          maxLines: 6,
        ),
        const SizedBox(height: 16),
        EventWizardLabel(S.eventWizardStarts),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: EventWizardPickerField(
                fieldKey: const ValueKey('event-wizard-start-date'),
                label: S.eventWizardDate,
                icon: Icons.calendar_today_outlined,
                value: start == null ? null : _dateLabel(start),
                placeholder: S.eventWizardSelectStartDate,
                active: _activePicker == 'start-date',
                onTap: () => unawaited(_pickDate(true)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EventWizardPickerField(
                fieldKey: const ValueKey('event-wizard-start-time'),
                label: S.eventWizardTime,
                icon: Icons.schedule_rounded,
                value: start == null ? null : _timeLabel(start),
                placeholder: S.eventWizardSelectStart,
                active: _activePicker == 'start-time',
                onTap: () => unawaited(_pickTime(true)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        EventWizardLabel(S.eventWizardEnds),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: EventWizardPickerField(
                fieldKey: const ValueKey('event-wizard-end-date'),
                label: S.eventWizardDate,
                icon: Icons.calendar_today_outlined,
                value: end == null ? null : _dateLabel(end),
                placeholder: S.eventWizardSelectEndDate,
                active: _activePicker == 'end-date',
                onTap: () => unawaited(_pickDate(false)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EventWizardPickerField(
                fieldKey: const ValueKey('event-wizard-end-time'),
                label: S.eventWizardTime,
                icon: Icons.schedule_rounded,
                value: end == null ? null : _timeLabel(end),
                placeholder: S.eventWizardSelectEnd,
                active: _activePicker == 'end-time',
                onTap: () => unawaited(_pickTime(false)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        EventWizardPickerField(
          fieldKey: const ValueKey('event-wizard-audience'),
          label: S.audienceFieldLabel,
          icon: Icons.visibility_outlined,
          value: S.audienceTierLabel(_selectedAudience),
          placeholder: S.audienceTierLabel(ContentAudience.everyone),
          active: _activePicker == 'audience',
          onTap: () => unawaited(_pickAudience()),
        ),
      ],
    );
  }

  // ── Step 2 of 3 — `light-speakers` 310:62 ────────────────────────────────
  Widget _buildSpeakersStep() {
    return ListView(
      key: const ValueKey('event-wizard-step-speakers'),
      padding: const EdgeInsets.all(kEventWizardGutter),
      children: [
        EventWizardLabel(S.eventWizardTagsLabel),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: EventWizardInputBox(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: TextField(
                  key: const ValueKey('event-wizard-tag-field'),
                  controller: _customTagCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTag(),
                  style: figtree(
                    size: 14,
                    weight: FontWeight.w400,
                    color: EventWizardColors.text,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    // EventWizardInputBox paints the only surface and border.
                    // Do not inherit the global grey fill or focus ring.
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: S.eventWizardTagHint,
                    hintStyle: figtree(
                      size: 14,
                      weight: FontWeight.w400,
                      color: EventWizardColors.placeholder,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            EventWizardAddButton(
              buttonKey: const ValueKey('event-wizard-tag-add'),
              label: AppLocalizations.of(context)!.add,
              onTap: _addTag,
            ),
          ],
        ),
        if (_selectedTags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _selectedTags)
                EventWizardTagChip(
                  label: tag,
                  onRemove: () => setState(() => _selectedTags.remove(tag)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.speakers,
                style: figtree(
                  size: 14,
                  weight: FontWeight.w700,
                  color: EventWizardColors.text,
                ),
              ),
            ),
            EventWizardTextAction(
              actionKey: const ValueKey('event-wizard-add-speaker'),
              label: S.eventWizardAddSpeaker,
              onTap: () => unawaited(_openSpeakerSheet()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _speakers.length; i++)
          if (_speakers[i].nameCtrl.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: EventWizardSpeakerCard(
                name: _speakers[i].nameCtrl.text.trim(),
                role: _speakers[i].roleCtrl.text.trim(),
                linkedin: _speakers[i].linkedinCtrl.text.trim(),
                onEdit: () => unawaited(_openSpeakerSheet(index: i)),
                onRemove: () => setState(() {
                  _speakers[i].dispose();
                  _speakers.removeAt(i);
                }),
              ),
            ),
        EventWizardDashedButton(
          buttonKey: const ValueKey('event-wizard-add-another-speaker'),
          label: _speakers.isEmpty
              ? S.eventWizardAddSpeaker
              : S.eventWizardAddAnotherSpeaker,
          onTap: () => unawaited(_openSpeakerSheet()),
        ),
        const SizedBox(height: 20),
        // `add-registration-link-btn` 310:121 reveals the field of
        // `speakers-expanded` 325:6. The old switch is gone.
        if (!_externalReg)
          Align(
            alignment: Alignment.centerLeft,
            child: EventWizardTextAction(
              actionKey: const ValueKey('event-wizard-add-registration'),
              label: S.eventWizardAddRegistrationLink,
              onTap: () => setState(() => _externalReg = true),
            ),
          )
        else
          EventWizardTextField(
            fieldKey: const ValueKey('event-wizard-registration-field'),
            controller: _regUrlCtrl,
            label: S.eventWizardRegistrationLabel,
            hint: S.eventWizardRegistrationHint,
            icon: Icons.link_rounded,
            keyboardType: TextInputType.url,
          ),
      ],
    );
  }

  // ── Step 3 of 3 — `light-preview` 310:133 / `add-session` 325:485 ────────
  Widget _buildProgrammeStep() {
    final rows = _sessionRows;
    return ListView(
      key: const ValueKey('event-wizard-step-programme'),
      padding: const EdgeInsets.all(kEventWizardGutter),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                S.eventWizardProgrammeSchedule,
                style: figtree(
                  size: 14,
                  weight: FontWeight.w700,
                  color: EventWizardColors.text,
                ),
              ),
            ),
            EventWizardTextAction(
              actionKey: const ValueKey('event-wizard-add-session'),
              label: S.eventWizardAddSession,
              onTap: () => unawaited(_openSessionSheet()),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_scheduleEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              S.eventWizardNoSessions,
              style: figtree(
                size: 13,
                weight: FontWeight.w400,
                color: EventWizardColors.muted,
              ),
            ),
          )
        else
          for (var i = 0; i < _scheduleEntries.length; i++)
            EventWizardSessionRow(
              title: _scheduleEntries[i].titleCtrl.text.trim(),
              speaker: _scheduleEntries[i].subtitleCtrl.text.trim(),
              time: TimeOfDay(
                hour: _scheduleEntries[i].time.hour,
                minute: _scheduleEntries[i].time.minute,
              ).format(context),
              onEdit: () => unawaited(_openSessionSheet(index: i)),
              onRemove: () => _removeScheduleEntry(i),
              showDivider: i != _scheduleEntries.length - 1,
            ),
        const SizedBox(height: 24),
        EventWizardLabel(S.eventWizardLivePreview),
        const SizedBox(height: 10),
        EventWizardLivePreviewCard(
          imagePath: _imagePath,
          title: _titleController.text.trim(),
          location: _locationController.text.trim(),
          whenLabel: _whenLabel,
          speakerCount: _speakerDrafts.length,
          sessionCount: rows.length,
        ),
      ],
    );
  }

  // ── The Event Preview page — `light-details` 324:978 ─────────────────────
  Widget _buildPreviewStep() {
    final start = _startDate;
    final end = _endDate;
    return EventWizardPreviewBody(
      imagePath: _imagePath,
      title: _titleController.text.trim(),
      location: _locationController.text.trim(),
      dateLabel: start == null ? '' : _longDateLabel(start),
      timeLabel: start == null
          ? ''
          : end == null
          ? _timeLabel(start)
          : '${_timeLabel(start)} – ${_timeLabel(end)}',
      description: _descController.text,
      tags: List<String>.from(_selectedTags),
      speakers: _speakerDrafts,
      sessions: _sessionRows,
    );
  }
}

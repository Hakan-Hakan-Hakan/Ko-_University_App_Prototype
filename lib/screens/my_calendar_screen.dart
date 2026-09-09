import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/event.dart' as app_event;
import '../services/app_colors.dart';
import '../services/auth_service.dart';
import '../services/calendar_sync_service.dart';
import '../services/mock_data.dart';
import '../services/rsvp_store.dart';
import '../services/content_visibility.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

enum CalEventType { calClass, event, deadline, personal }

extension CalEventTypeX on CalEventType {
  String label(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (this) {
      case CalEventType.calClass:
        return l10n.calEventTypeClass;
      case CalEventType.event:
        return l10n.calEventTypeEvent;
      case CalEventType.deadline:
        return l10n.calEventTypeDeadline;
      case CalEventType.personal:
        return l10n.calEventTypePersonal;
    }
  }

  Color get color {
    switch (this) {
      case CalEventType.calClass:
        return const Color(0xFF1565C0);
      case CalEventType.event:
        return AppColors.primaryRed;
      case CalEventType.deadline:
        return const Color(0xFFE65100);
      case CalEventType.personal:
        return const Color(0xFF00838F);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class CalEvent {
  final String id;
  final String?
  sourceEventId; // set for CalEventType.event — links to app Event.id
  final int day;
  final int month; // 0-indexed (0=Jan)
  final int year;
  final CalEventType type;
  final String title;
  final String time;
  final String endTime;
  final String location;
  final bool isUserAdded;

  const CalEvent({
    required this.id,
    this.sourceEventId,
    required this.day,
    required this.month,
    required this.year,
    required this.type,
    required this.title,
    required this.time,
    required this.endTime,
    this.location = '',
    this.isUserAdded = false,
  });

  CalEvent copyWith({
    int? day,
    int? month,
    int? year,
    CalEventType? type,
    String? title,
    String? time,
    String? endTime,
    String? location,
  }) => CalEvent(
    id: id,
    sourceEventId: sourceEventId,
    day: day ?? this.day,
    month: month ?? this.month,
    year: year ?? this.year,
    type: type ?? this.type,
    title: title ?? this.title,
    time: time ?? this.time,
    endTime: endTime ?? this.endTime,
    location: location ?? this.location,
    isUserAdded: true,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Seed data generator
// ─────────────────────────────────────────────────────────────────────────────

String _fmt(int n) => n.toString().padLeft(2, '0');

List<CalEvent> buildMonthEvents(int year, int month) {
  final result = <CalEvent>[];

  // Only include app events the user has RSVP'd to
  for (final e in events) {
    if (!rsvpStore.isAttending(e.id)) continue;
    if (!canViewEvent(e)) continue;
    final dt = e.dateTime;
    if (dt.year == year && dt.month == month + 1) {
      result.add(
        CalEvent(
          id: 'appev_${e.id}',
          sourceEventId: e.id,
          day: dt.day,
          month: month,
          year: year,
          type: CalEventType.event,
          title: e.title,
          time: '${_fmt(dt.hour)}:${_fmt(dt.minute)}',
          endTime: '${_fmt(e.endTime.hour)}:${_fmt(e.endTime.minute)}',
          location: e.location,
        ),
      );
    }
  }

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// MyCalendarScreen
// ─────────────────────────────────────────────────────────────────────────────

class MyCalendarScreen extends StatefulWidget {
  const MyCalendarScreen({super.key});

  @override
  State<MyCalendarScreen> createState() => _MyCalendarScreenState();
}

class _MyCalendarScreenState extends State<MyCalendarScreen> {
  late int _month; // 0-indexed
  late int _year;
  late int _selDay;
  CalEventType? _filter; // null = all
  List<CalEvent> _userEvents = [];

  List<String> get _months {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.monthJanuary,
      l10n.monthFebruary,
      l10n.monthMarch,
      l10n.monthApril,
      l10n.monthMay,
      l10n.monthJune,
      l10n.monthJuly,
      l10n.monthAugust,
      l10n.monthSeptember,
      l10n.monthOctober,
      l10n.monthNovember,
      l10n.monthDecember,
    ];
  }

  List<String> get _dowShort {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.dowMon,
      l10n.dowTue,
      l10n.dowWed,
      l10n.dowThu,
      l10n.dowFri,
      l10n.dowSat,
      l10n.dowSun,
    ];
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month - 1;
    _year = now.year;
    _selDay = now.day;
  }

  int get _today => DateTime.now().day;
  int get _todayMonth => DateTime.now().month - 1;
  int get _todayYear => DateTime.now().year;
  bool get _isCurrentMonth => _month == _todayMonth && _year == _todayYear;

  List<CalEvent> get _allMonthEvents {
    final seed = buildMonthEvents(_year, _month);
    final user = _userEvents.where((e) => e.month == _month && e.year == _year);
    return [...seed, ...user];
  }

  List<CalEvent> _dayEvents(int day) {
    return _allMonthEvents.where((e) {
      if (e.day != day) return false;
      if (_filter != null && e.type != _filter) return false;
      return true;
    }).toList()..sort((a, b) => a.time.compareTo(b.time));
  }

  int get _monthCount =>
      _allMonthEvents.where((e) => _filter == null || e.type == _filter).length;

  void _shiftMonth(int delta) {
    setState(() {
      var m = _month + delta;
      var y = _year;
      if (m < 0) {
        m = 11;
        y--;
      } else if (m > 11) {
        m = 0;
        y++;
      }
      _month = m;
      _year = y;
      _selDay = 1;
    });
  }

  void _jumpToday() {
    setState(() {
      _month = _todayMonth;
      _year = _todayYear;
      _selDay = _today;
    });
  }

  void _openNewEvent() {
    _showComposer(
      initialDay: _selDay,
      initialMonth: _month,
      initialYear: _year,
    );
  }

  void _openEditEvent(CalEvent e) {
    _showComposer(existing: e);
  }

  Future<void> _showComposer({
    CalEvent? existing,
    int? initialDay,
    int? initialMonth,
    int? initialYear,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EventComposerSheet(
        existing: existing,
        initialDay: initialDay ?? _selDay,
        initialMonth: initialMonth ?? _month,
        initialYear: initialYear ?? _year,
        onSave: (e) {
          setState(() {
            if (existing != null) {
              _userEvents = [
                for (final u in _userEvents)
                  if (u.id == e.id) e else u,
              ];
            } else {
              _userEvents = [..._userEvents, e];
            }
            _month = e.month;
            _year = e.year;
            _selDay = e.day;
          });
        },
        onDelete: existing == null
            ? null
            : (id) {
                setState(() {
                  _userEvents = [
                    for (final u in _userEvents)
                      if (u.id != id) u,
                  ];
                });
              },
      ),
    );
  }

  // ── Month grid cells ─────────────────────────────────────────────────────

  List<({int d, bool out})> get _gridCells {
    final firstDow = (DateTime(_year, _month + 1, 1).weekday - 1) % 7; // 0=Mon
    final daysInMonth = DateTime(_year, _month + 2, 0).day;
    final prevDays = DateTime(_year, _month + 1, 0).day;
    final cells = <({int d, bool out})>[];
    for (int i = 0; i < firstDow; i++) {
      cells.add((d: prevDays - firstDow + 1 + i, out: true));
    }
    for (int i = 1; i <= daysInMonth; i++) {
      cells.add((d: i, out: false));
    }
    while (cells.length % 7 != 0 || cells.length < 35) {
      cells.add((d: cells.length - firstDow - daysInMonth + 1, out: true));
    }
    return cells;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cells = _gridCells;
    final selected = _dayEvents(_selDay);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildMonthHeader(),
            _buildFilterChips(),
            _buildDowHeader(),
            _buildMonthGrid(cells),
            const Divider(height: 1, thickness: 0.5),
            Expanded(child: _buildAgenda(selected)),
          ],
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // Back
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: AppColors.divider),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.myCalendarTitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  AppLocalizations.of(
                    context,
                  )!.calendarItemsThisMonth(_monthCount),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          // Today button
          GestureDetector(
            onTap: _jumpToday,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.all(Radius.circular(999)),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                AppLocalizations.of(context)!.today,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryRed,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // New event button
          GestureDetector(
            onTap: _openNewEvent,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primaryRed,
                borderRadius: BorderRadius.all(Radius.circular(11)),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Month header with prev/next ──────────────────────────────────────────

  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                      letterSpacing: -1.4,
                      height: 1,
                    ),
                    children: [
                      TextSpan(text: _months[_month]),
                      TextSpan(
                        text: '.',
                        style: TextStyle(color: AppColors.primaryRed),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_year',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _ArrowBtn(
                icon: Icons.chevron_left_rounded,
                onTap: () => _shiftMonth(-1),
              ),
              const SizedBox(width: 6),
              _ArrowBtn(
                icon: Icons.chevron_right_rounded,
                onTap: () => _shiftMonth(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Filter chips ─────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    final l10n = AppLocalizations.of(context)!;
    final filters = [
      (
        type: null as CalEventType?,
        label: l10n.all,
        color: AppColors.primaryRed,
      ),
      (
        type: CalEventType.event,
        label: l10n.calendarFilterRsvpd,
        color: CalEventType.event.color,
      ),
      (
        type: CalEventType.personal,
        label: l10n.calEventTypePersonal,
        color: CalEventType.personal.color,
      ),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (context2, i2) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final f = filters[i];
          final active = _filter == f.type;
          return GestureDetector(
            onTap: () => setState(() => _filter = f.type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active
                    ? f.color.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.all(Radius.circular(999)),
                border: Border.all(color: active ? f.color : AppColors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.type != null) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: f.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    f.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? f.color : AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Day-of-week header ───────────────────────────────────────────────────

  Widget _buildDowHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          for (final d in _dowShort)
            Expanded(
              child: Text(
                d,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Month grid ────────────────────────────────────────────────────────────

  Widget _buildMonthGrid(List<({int d, bool out})> cells) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 1 / 1.05,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: cells.length,
        itemBuilder: (ctx, i) {
          final cell = cells[i];
          if (cell.out) {
            return Center(
              child: Text(
                '${cell.d}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text.withValues(alpha: 0.25),
                ),
              ),
            );
          }
          final isToday = _isCurrentMonth && cell.d == _today;
          final isSelected = cell.d == _selDay;
          final evs = _dayEvents(cell.d);

          return GestureDetector(
            onTap: () => setState(() => _selDay = cell.d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isToday
                    ? AppColors.primaryRed
                    : isSelected
                    ? AppColors.card
                    : Colors.transparent,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.all(
                  color: isSelected && !isToday
                      ? AppColors.primaryRed
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    '${cell.d}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isToday
                          ? FontWeight.w800
                          : isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isToday ? Colors.white : AppColors.text,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (evs.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final e in evs.take(3))
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : e.type.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (evs.length > 3)
                      Text(
                        '+${evs.length - 3}',
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                          color: isToday
                              ? Colors.white.withValues(alpha: 0.7)
                              : AppColors.secondaryText,
                          letterSpacing: 0.3,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Agenda ────────────────────────────────────────────────────────────────

  Widget _buildAgenda(List<CalEvent> selected) {
    final label = _isCurrentMonth && _selDay == _today
        ? AppLocalizations.of(context)!.today
        : '${_months[_month].substring(0, 3)} $_selDay';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        // Agenda header
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryText,
                letterSpacing: 1.0,
                textBaseline: TextBaseline.alphabetic,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: AppColors.divider)),
            const SizedBox(width: 10),
            Text(
              AppLocalizations.of(context)!.calendarItemsCount(selected.length),
              style: TextStyle(
                fontSize: 10,
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (selected.isEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    size: 20,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!.calendarNothingScheduled,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _openNewEvent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed,
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.calendarAddEventButton,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          for (final e in selected) ...[
            _AgendaItem(
              event: e,
              onTap: e.isUserAdded ? () => _openEditEvent(e) : null,
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Agenda item row
// ─────────────────────────────────────────────────────────────────────────────

class _AgendaItem extends StatefulWidget {
  final CalEvent event;
  final VoidCallback? onTap;

  const _AgendaItem({required this.event, this.onTap});

  @override
  State<_AgendaItem> createState() => _AgendaItemState();
}

class _AgendaItemState extends State<_AgendaItem> {
  bool _syncing = false;

  String get _userId =>
      authService.currentUser?.id ?? authService.currentAdmin?.id ?? '';

  app_event.Event? get _sourceEvent {
    final sid = widget.event.sourceEventId;
    if (sid == null) return null;
    try {
      return events.firstWhere((e) => e.id == sid);
    } catch (_) {
      return null;
    }
  }

  bool get _isRsvpd {
    final sid = widget.event.sourceEventId;
    if (sid == null) return false;
    return rsvpStore.isAttending(sid);
  }

  bool get _isSynced {
    final sid = widget.event.sourceEventId;
    if (sid == null) return false;
    return calendarSyncService.isSynced(_userId, sid);
  }

  Future<void> _handleAddToPhone() async {
    if (_syncing || _isSynced) return;
    final src = _sourceEvent;
    if (src == null) return;

    // Check current permission status
    final status = await calendarSyncService.checkPermission();

    if (!mounted) return;

    if (status == 'authorized') {
      _doSync(src);
      return;
    }

    if (status == 'denied' || status == 'restricted') {
      _showDeniedDialog();
      return;
    }

    // notDetermined — show explanation dialog first, then trigger native prompt
    await _showPrePermissionDialog();
    if (!mounted) return;
    final granted = await calendarSyncService.requestPermission();
    if (!mounted) return;
    if (granted) {
      _doSync(src);
    } else {
      _showDeniedDialog();
    }
  }

  Future<void> _showPrePermissionDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primaryRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                size: 30,
                color: AppColors.primaryRed,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.allowCalendarAccessTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context)!.calendarPrePermissionBody,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.secondaryText,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      side: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.notNow,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.allowAccessButton,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDeniedDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 30,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.calendarAccessDeniedTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context)!.calendarDeniedBody,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              child: Text(
                AppLocalizations.of(context)!.gotIt,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doSync(app_event.Event src) async {
    setState(() => _syncing = true);
    await calendarSyncService.addToDeviceCalendar(src, _userId);
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.event.type;
    final color = meta.color;
    final isAppEvent =
        widget.event.type == CalEventType.event &&
        widget.event.sourceEventId != null;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time column
            SizedBox(
              width: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.event.time,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: -0.2,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.event.endTime,
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Colored vertical bar
            Container(
              width: 3,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                        ),
                        child: Text(
                          meta.label(context).toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: color,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (isAppEvent && _isRsvpd) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1B5E20,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.all(Radius.circular(6)),
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.calendarRsvpdBadge,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4CAF50),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                      if (widget.onTap != null && !isAppEvent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.all(Radius.circular(6)),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!.calendarYoursTapToEdit,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.secondaryText,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.event.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.event.location.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '· ${widget.event.location}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isAppEvent) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: (_isSynced || _syncing) ? null : _handleAddToPhone,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _isSynced
                              ? const Color(0xFF1B5E20).withValues(alpha: 0.12)
                              : AppColors.primaryRed.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          border: Border.all(
                            color: _isSynced
                                ? const Color(0xFF4CAF50).withValues(alpha: 0.4)
                                : AppColors.primaryRed.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_syncing)
                              SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppColors.primaryRed,
                                ),
                              )
                            else
                              Icon(
                                _isSynced
                                    ? Icons.check_circle_rounded
                                    : Icons.calendar_today_rounded,
                                size: 11,
                                color: _isSynced
                                    ? const Color(0xFF4CAF50)
                                    : AppColors.primaryRed,
                              ),
                            const SizedBox(width: 5),
                            Text(
                              _syncing
                                  ? AppLocalizations.of(context)!.addingEllipsis
                                  : _isSynced
                                  ? AppLocalizations.of(
                                      context,
                                    )!.calendarAddedToPhone
                                  : AppLocalizations.of(
                                      context,
                                    )!.calendarAddToPhone,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _isSynced
                                    ? const Color(0xFF4CAF50)
                                    : AppColors.primaryRed,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arrow button (month nav)
// ─────────────────────────────────────────────────────────────────────────────

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.all(Radius.circular(11)),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, size: 18, color: AppColors.secondaryText),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Event composer bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EventComposerSheet extends StatefulWidget {
  final CalEvent? existing;
  final int initialDay;
  final int initialMonth;
  final int initialYear;
  final void Function(CalEvent) onSave;
  final void Function(String)? onDelete;

  const _EventComposerSheet({
    this.existing,
    required this.initialDay,
    required this.initialMonth,
    required this.initialYear,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_EventComposerSheet> createState() => _EventComposerSheetState();
}

class _EventComposerSheetState extends State<_EventComposerSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _locCtrl;
  late CalEventType _type;
  late int _day;
  late int _month;
  late int _year;
  late String _startTime;
  late String _endTime;

  bool get _isEdit => widget.existing != null;
  bool get _canSave => _titleCtrl.text.trim().isNotEmpty;

  List<String> get _months {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.monthJanuary,
      l10n.monthFebruary,
      l10n.monthMarch,
      l10n.monthApril,
      l10n.monthMay,
      l10n.monthJune,
      l10n.monthJuly,
      l10n.monthAugust,
      l10n.monthSeptember,
      l10n.monthOctober,
      l10n.monthNovember,
      l10n.monthDecember,
    ];
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _locCtrl = TextEditingController(text: e?.location ?? '');
    _type = e?.type ?? CalEventType.personal;
    _day = e?.day ?? widget.initialDay;
    _month = e?.month ?? widget.initialMonth;
    _year = e?.year ?? widget.initialYear;
    _startTime = e?.time ?? '12:00';
    _endTime = e?.endTime ?? '13:00';
    _titleCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) return;
    final id = _isEdit
        ? widget.existing!.id
        : 'u${DateTime.now().millisecondsSinceEpoch}';
    widget.onSave(
      CalEvent(
        id: id,
        day: _day,
        month: _month,
        year: _year,
        type: _type,
        title: _titleCtrl.text.trim(),
        time: _startTime,
        endTime: _endTime,
        location: _locCtrl.text.trim(),
        isUserAdded: true,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_year, _month + 1, _day),
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.primaryRed,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _day = picked.day;
        _month = picked.month - 1;
        _year = picked.year;
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final parts = (isStart ? _startTime : _endTime)
        .split(':')
        .map(int.parse)
        .toList();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.primaryRed,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final str =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() => isStart ? _startTime = str : _endTime = str);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),

              // Header row
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      AppLocalizations.of(context)!.cancel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _isEdit
                          ? AppLocalizations.of(context)!.calendarEditEvent
                          : AppLocalizations.of(context)!.calendarNewEvent,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _canSave ? _save : null,
                    child: Text(
                      _isEdit
                          ? AppLocalizations.of(context)!.save
                          : AppLocalizations.of(context)!.calendarAdd,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _canSave
                            ? AppColors.primaryRed
                            : AppColors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Type selector
              _SectionLabel(AppLocalizations.of(context)!.typeLabel),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final t in CalEventType.values) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _type == t
                                ? t.color.withValues(alpha: 0.15)
                                : AppColors.background,
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            border: Border.all(
                              color: _type == t ? t.color : AppColors.divider,
                              width: _type == t ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: t.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                t.label(context),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _type == t
                                      ? t.color
                                      : AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (t != CalEventType.values.last) const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: 14),

              // Title
              _SectionLabel(AppLocalizations.of(context)!.titleFieldLabel),
              const SizedBox(height: 8),
              _Field(
                controller: _titleCtrl,
                hint: AppLocalizations.of(context)!.whatsHappeningHint,
                autofocus: true,
              ),
              const SizedBox(height: 14),

              // Date
              _SectionLabel(AppLocalizations.of(context)!.dateLabel),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.all(Radius.circular(11)),
                  ),
                  child: Text(
                    '${_months[_month]} $_day, $_year',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Time row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          AppLocalizations.of(context)!.startsLabel,
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _pickTime(true),
                          child: _TimeBox(time: _startTime),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(AppLocalizations.of(context)!.endsLabel),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _pickTime(false),
                          child: _TimeBox(time: _endTime),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Location
              _SectionLabel(
                AppLocalizations.of(context)!.locationOptionalLabel,
              ),
              const SizedBox(height: 8),
              _Field(
                controller: _locCtrl,
                hint: AppLocalizations.of(context)!.whereHint,
              ),
              const SizedBox(height: 18),

              // Preview chip
              Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                decoration: BoxDecoration(
                  color: _type.color.withValues(alpha: 0.10),
                  border: Border.all(
                    color: _type.color.withValues(alpha: 0.30),
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _type.color,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.calendarPreviewLabel(
                              _type.label(context).toUpperCase(),
                            ),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: _type.color,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _titleCtrl.text.isEmpty
                                ? AppLocalizations.of(context)!.untitledLabel
                                : _titleCtrl.text,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_months[_month].substring(0, 3)} $_day · $_startTime–$_endTime${_locCtrl.text.isNotEmpty ? ' · ${_locCtrl.text}' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_isEdit) ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    widget.onDelete?.call(widget.existing!.id);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      border: Border.all(color: AppColors.divider),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      AppLocalizations.of(context)!.calendarDeleteEventButton,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFEF5350),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: AppColors.secondaryText,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool autofocus;

  const _Field({
    required this.controller,
    required this.hint,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: TextStyle(
        fontSize: 14,
        color: AppColors.text,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.secondaryText),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 12,
        ),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
          borderSide: BorderSide(color: AppColors.primaryRed),
        ),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String time;
  const _TimeBox({required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.all(Radius.circular(11)),
      ),
      child: Text(
        time,
        style: TextStyle(
          fontSize: 14,
          color: AppColors.text,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

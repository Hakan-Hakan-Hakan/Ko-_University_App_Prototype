import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/personalization_service.dart'
    show normalizeAcademicProgramName;
import 'search_design.dart';

/// Which side of the directory the query runs against — the "Search In" cards
/// at the top of the Filters sheet.
enum SearchScope { clubs, students }

/// The club-side "Sort By" radio group.
enum ClubSort { members, recentlyActive }

/// Everything the Filters sheet can change. Immutable so the sheet can edit a
/// draft and only hand it back when Apply is tapped.
@immutable
class SearchFilters {
  final SearchScope scope;
  final ClubSort clubSort;
  final Set<String> categories;
  final Set<String> majors;
  final Set<String> years;

  const SearchFilters({
    this.scope = SearchScope.clubs,
    this.clubSort = ClubSort.members,
    this.categories = const {},
    this.majors = const {},
    this.years = const {},
  });

  SearchFilters copyWith({
    SearchScope? scope,
    ClubSort? clubSort,
    Set<String>? categories,
    Set<String>? majors,
    Set<String>? years,
  }) {
    return SearchFilters(
      scope: scope ?? this.scope,
      clubSort: clubSort ?? this.clubSort,
      categories: categories ?? this.categories,
      majors: majors ?? this.majors,
      years: years ?? this.years,
    );
  }

  /// True when nothing narrows the result set — the search screen shows its
  /// discovery sections instead of a result list in that case.
  bool get isEmpty => categories.isEmpty && majors.isEmpty && years.isEmpty;

  /// Number of active narrowing choices, for the badge on the filter icon.
  int get activeCount => categories.length + majors.length + years.length;
}

@immutable
class SearchFilterResult {
  final SearchFilters filters;
  final bool resetToDiscovery;

  const SearchFilterResult.applied(this.filters) : resetToDiscovery = false;

  const SearchFilterResult.reset()
    : filters = const SearchFilters(),
      resetToDiscovery = true;
}

/// Opens the Filters sheet. Returns either applied filters or an explicit
/// request to restore the original discovery UI; null means it was dismissed.
/// [yearLabelOf] maps a stored year value ("1st Year") to its localized label.
/// The raw value is what gets filtered on, so only the tag caption changes.
Future<SearchFilterResult?> showSearchFilterSheet({
  required BuildContext context,
  required SearchFilters filters,
  required List<String> categories,
  required List<String> majors,
  required List<String> years,
  String Function(String)? yearLabelOf,
}) {
  return showModalBottomSheet<SearchFilterResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: SearchColors.scrim,
    builder: (_) => _SearchFilterSheet(
      initial: filters,
      categories: categories,
      majors: majors,
      years: years,
      yearLabelOf: yearLabelOf,
    ),
  );
}

class _SearchFilterSheet extends StatefulWidget {
  final SearchFilters initial;
  final List<String> categories;
  final List<String> majors;
  final List<String> years;
  final String Function(String)? yearLabelOf;

  const _SearchFilterSheet({
    required this.initial,
    required this.categories,
    required this.majors,
    required this.years,
    this.yearLabelOf,
  });

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late SearchFilters _draft = widget.initial;

  bool get _isClubs => _draft.scope == SearchScope.clubs;

  void _toggle(Set<String> from, String value, void Function(Set<String>) set) {
    final next = {...from};
    if (!next.add(value)) next.remove(value);
    set(next);
  }

  Future<void> _pickMajors() async {
    final result = await showSearchMajorPicker(
      context: context,
      selected: _draft.majors,
      programs: widget.majors,
    );
    if (result == null || !mounted) return;
    setState(() => _draft = _draft.copyWith(majors: result));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: BoxDecoration(
        color: SearchColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            offset: Offset(0, -10),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _handle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: _header(l10n),
            ),
            const SizedBox(height: 24),
            Divider(height: 1, thickness: 1, color: SearchColors.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _searchInSection(l10n),
                    const SizedBox(height: 24),
                    _sortBySection(l10n),
                    const SizedBox(height: 24),
                    if (_isClubs)
                      _tagSection(
                        title: l10n.categoriesLabel,
                        options: widget.categories,
                        selected: _draft.categories,
                        onTap: (value) => _toggle(
                          _draft.categories,
                          value,
                          (next) => setState(
                            () => _draft = _draft.copyWith(categories: next),
                          ),
                        ),
                      )
                    else
                      _tagSection(
                        title: l10n.yearLabel,
                        options: widget.years,
                        selected: _draft.years,
                        labelOf: widget.yearLabelOf,
                        onTap: (value) => _toggle(
                          _draft.years,
                          value,
                          (next) => setState(
                            () => _draft = _draft.copyWith(years: next),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: _bottomActions(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle() {
    return Container(
      width: 36,
      height: 5,
      decoration: BoxDecoration(
        color: SearchColors.border,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(width: 28),
        Text(
          l10n.filtersTitle,
          style: figtree(
            size: 18,
            weight: FontWeight.w800,
            color: SearchColors.text,
          ),
        ),
        _CircleIconButton(
          icon: Icons.close_rounded,
          onTap: () => Navigator.pop(context),
          semanticLabel: MaterialLocalizations.of(context).closeButtonTooltip,
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: figtree(
        size: 14,
        weight: FontWeight.w800,
        color: SearchColors.text,
      ),
    );
  }

  Widget _searchInSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.searchInLabel),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ScopeCard(
                key: const ValueKey('search-scope-clubs'),
                icon: Icons.groups_outlined,
                label: l10n.clubs,
                selected: _isClubs,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(scope: SearchScope.clubs),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ScopeCard(
                key: const ValueKey('search-scope-students'),
                icon: Icons.person_outline_rounded,
                label: l10n.students,
                selected: !_isClubs,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(scope: SearchScope.students),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sortBySection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.sortByLabel),
        const SizedBox(height: 8),
        if (_isClubs) ...[
          _RadioRow(
            label: l10n.sortMostMembers,
            selected: _draft.clubSort == ClubSort.members,
            onTap: () => setState(
              () => _draft = _draft.copyWith(clubSort: ClubSort.members),
            ),
          ),
          _RadioRow(
            label: l10n.sortRecentlyActive,
            selected: _draft.clubSort == ClubSort.recentlyActive,
            onTap: () => setState(
              () => _draft = _draft.copyWith(clubSort: ClubSort.recentlyActive),
            ),
          ),
        ] else
          _RadioRow(
            key: const ValueKey('people-major-filter'),
            label: _draft.majors.isEmpty
                ? l10n.majorLabel
                : '${l10n.majorLabel} · ${_draft.majors.length}',
            selected: _draft.majors.isNotEmpty,
            onTap: _pickMajors,
          ),
      ],
    );
  }

  Widget _tagSection({
    required String title,
    required List<String> options,
    required Set<String> selected,
    required ValueChanged<String> onTap,
    String Function(String)? labelOf,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              _Tag(
                label: labelOf?.call(option) ?? option,
                selected: selected.contains(option),
                onTap: () => onTap(option),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bottomActions(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _SecondaryPillButton(
            key: const ValueKey('clear-people-major-filter'),
            label: l10n.resetFilters,
            onTap: () =>
                Navigator.pop(context, const SearchFilterResult.reset()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PrimaryPillButton(
            key: const ValueKey('search-filters-apply'),
            label: l10n.applyLabel,
            onTap: () =>
                Navigator.pop(context, SearchFilterResult.applied(_draft)),
          ),
        ),
      ],
    );
  }
}

// ─── Sheet atoms ─────────────────────────────────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SearchColors.chip,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 14, color: SearchColors.text),
        ),
      ),
    );
  }
}

class _ScopeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ScopeCard({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? SearchColors.accentSurface : SearchColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? SearchColors.accent : SearchColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? SearchColors.accentText : SearchColors.muted,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figtree(
                    size: 14,
                    weight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? SearchColors.accentText
                        : SearchColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: figtree(
                  size: 14,
                  weight: FontWeight.w500,
                  color: SearchColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? SearchColors.accent : SearchColors.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: SearchColors.accent,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tag({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? SearchColors.accent : SearchColors.chip,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected ? SearchColors.accent : SearchColors.border,
            ),
          ),
          child: Text(
            label,
            style: figtree(
              size: 13,
              weight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : SearchColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SecondaryPillButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SearchColors.card,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: SearchColors.accent, width: 1.5),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: figtree(
              size: 15,
              weight: FontWeight.w700,
              color: SearchColors.accentText,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TextAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          label,
          style: figtree(
            size: 15,
            weight: FontWeight.w700,
            color: SearchColors.muted,
          ),
        ),
      ),
    );
  }
}

class _PrimaryPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryPillButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 14),
        decoration: BoxDecoration(
          color: SearchColors.accent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: figtree(
            size: 15,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─── Select Major ────────────────────────────────────────────────────────────

/// Koç University's colleges, used to group the flat [kAcademicPrograms] list
/// into the section headers the `clubup-major` frame shows. The Figma frame
/// uses placeholder majors ("Computer Science", "Graphic Design"); the real
/// programme list is what ships, grouped by the college that offers it. Any
/// programme not named here falls into the trailing "other" group, so majors
/// that arrive from the backend still appear.
const Map<String, List<String>> kProgramColleges = {
  'Engineering': [
    'Chemical and Biological Engineering',
    'Computer Engineering',
    'Electrical and Electronics Engineering',
    'Industrial Engineering',
    'Mechanical Engineering',
  ],
  'Administrative Sciences and Economics': [
    'Business Administration',
    'Economics',
    'International Relations',
  ],
  'Social Sciences and Humanities': [
    'Archaeology and History of Art',
    'Comparative Literature',
    'History',
    'Media and Visual Arts',
    'Philosophy',
    'Psychology',
    'Sociology',
  ],
  'Sciences': [
    'Chemistry',
    'Mathematics',
    'Molecular Biology and Genetics',
    'Physics',
  ],
  'Law': ['Law'],
  'Medicine and Nursing': ['Medicine', 'Nursing'],
};

/// Opens the full-screen "Select Major" picker. Returns the chosen majors, or
/// null if dismissed without confirming.
Future<Set<String>?> showSearchMajorPicker({
  required BuildContext context,
  required Set<String> selected,
  required List<String> programs,
}) {
  return Navigator.of(context).push<Set<String>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _SearchMajorPicker(selected: selected, programs: programs),
    ),
  );
}

class _SearchMajorPicker extends StatefulWidget {
  final Set<String> selected;
  final List<String> programs;

  const _SearchMajorPicker({required this.selected, required this.programs});

  @override
  State<_SearchMajorPicker> createState() => _SearchMajorPickerState();
}

class _SearchMajorPickerState extends State<_SearchMajorPicker> {
  late final Set<String> _selected = {...widget.selected};
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The programme list grouped by college, filtered by the search query.
  /// Groups that end up empty are dropped so no bare header is rendered.
  List<MapEntry<String, List<String>>> get _groups {
    final query = _query.trim().toLowerCase();
    bool matches(String program) =>
        query.isEmpty || program.toLowerCase().contains(query);

    final grouped = <String, List<String>>{};
    final claimed = <String>{};

    for (final entry in kProgramColleges.entries) {
      final collegePrograms = entry.value
          .map(normalizeAcademicProgramName)
          .toSet();
      final items = widget.programs
          .where(
            (program) =>
                collegePrograms.contains(
                  normalizeAcademicProgramName(program),
                ) &&
                matches(program),
          )
          .toList();
      claimed.addAll(collegePrograms);
      if (items.isNotEmpty) grouped[entry.key] = items;
    }

    final other =
        widget.programs
            .where(
              (program) =>
                  !claimed.contains(normalizeAcademicProgramName(program)) &&
                  matches(program),
            )
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (other.isNotEmpty) {
      grouped[AppLocalizations.of(context)!.categoryAcademic] = other;
    }

    return grouped.entries.toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groups = _groups;

    return Scaffold(
      backgroundColor: SearchColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _header(l10n),
            _searchBar(l10n),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noMatchingMajor,
                        style: figtree(
                          size: 15,
                          weight: FontWeight.w500,
                          color: SearchColors.muted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: groups.length,
                      itemBuilder: (context, i) => _group(groups[i]),
                    ),
            ),
            _bottomActions(l10n),
          ],
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Semantics(
            button: true,
            label: MaterialLocalizations.of(context).backButtonTooltip,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(100),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: SearchColors.text,
                ),
              ),
            ),
          ),
          Text(
            l10n.selectMajorTitle,
            style: figtree(
              size: 18,
              weight: FontWeight.w800,
              color: SearchColors.text,
            ),
          ),
          _CircleIconButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.pop(context),
            semanticLabel: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
        ],
      ),
    );
  }

  Widget _searchBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: SearchColors.chip,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: SearchColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('academic-program-picker-search'),
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                style: figtree(
                  size: 14,
                  weight: FontWeight.w400,
                  color: SearchColors.text,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: l10n.searchMajorsHint,
                  hintStyle: figtree(
                    size: 14,
                    weight: FontWeight.w400,
                    color: SearchColors.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(MapEntry<String, List<String>> group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: SearchColors.chip,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Text(
            group.key.toUpperCase(),
            style: figtree(
              size: 12,
              weight: FontWeight.w700,
              color: SearchColors.muted,
            ),
          ),
        ),
        for (final program in group.value) _row(program),
      ],
    );
  }

  Widget _row(String program) {
    final selected = _selected.contains(program);
    return InkWell(
      key: ValueKey('academic-program-$program'),
      onTap: () => setState(() {
        if (!_selected.add(program)) _selected.remove(program);
      }),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    program,
                    style: figtree(
                      size: 15,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: SearchColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? SearchColors.accent : Colors.transparent,
                    border: selected
                        ? null
                        : Border.all(color: SearchColors.muted, width: 1.5),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: SearchColors.border),
        ],
      ),
    );
  }

  Widget _bottomActions(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: SearchColors.card,
        border: Border(top: BorderSide(color: SearchColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _TextAction(
            label: l10n.clearAll,
            onTap: () => setState(_selected.clear),
          ),
          _PrimaryPillButton(
            key: const ValueKey('major-picker-done'),
            label: _selected.isEmpty
                ? l10n.done
                : l10n.doneCount(_selected.length),
            onTap: () => Navigator.pop(context, _selected),
          ),
        ],
      ),
    );
  }
}

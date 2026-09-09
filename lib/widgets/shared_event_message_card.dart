import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../screens/event_detail_screen.dart';
import '../services/app_colors.dart';
import '../services/app_strings.dart';
import '../services/content_visibility.dart';
import '../services/mock_data.dart';
import '../services/supabase_content_service.dart';
import 'content_audience_sheet.dart';
import 'event_cover_image.dart';
import 'dynamic_contrast_text.dart';

typedef SharedEventResolver = Future<Event?> Function(String eventId);

/// Rich, tappable event preview rendered inside direct and group messages.
class SharedEventMessageCard extends StatefulWidget {
  const SharedEventMessageCard({
    super.key,
    required this.eventId,
    this.onDarkBackground = false,
    this.resolveEvent,
  });

  final String eventId;
  final bool onDarkBackground;
  final SharedEventResolver? resolveEvent;

  @override
  State<SharedEventMessageCard> createState() => _SharedEventMessageCardState();
}

class _SharedEventMessageCardState extends State<SharedEventMessageCard> {
  Event? _event;
  bool _isLoading = false;

  Event? _loadedEvent(String eventId) {
    for (final event in events) {
      if (event.id == eventId) return event;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _event = _loadedEvent(widget.eventId);
    if (_event == null) _resolveEvent();
  }

  @override
  void didUpdateWidget(covariant SharedEventMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId == widget.eventId) return;
    _event = _loadedEvent(widget.eventId);
    _isLoading = false;
    if (_event == null) _resolveEvent();
  }

  Future<void> _resolveEvent() async {
    final requestedId = widget.eventId;
    setState(() => _isLoading = true);
    final resolver =
        widget.resolveEvent ?? supabaseContentService.fetchEventById;
    Event? event;
    try {
      event = await resolver(requestedId);
    } catch (_) {
      event = null;
    }
    if (!mounted || requestedId != widget.eventId) return;
    setState(() {
      _event = event;
      _isLoading = false;
    });
  }

  static const _fallbackColors = <Color>[
    Color(0xFFB41C18),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00838F),
  ];

  Color _eventColor(Event event) {
    final hex = event.accentColorHex?.trim() ?? '';
    final parsed = int.tryParse('FF$hex', radix: 16);
    if (hex.length == 6 && parsed != null) return Color(parsed);
    final ordinal = clubOrdinal(event.clubId);
    return _fallbackColors[(ordinal < 0 ? 0 : ordinal) %
        _fallbackColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    if (event == null) {
      return Container(
        key: ValueKey(
          _isLoading
              ? 'shared-event-loading-${widget.eventId}'
              : 'shared-event-unavailable-${widget.eventId}',
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.onDarkBackground
              ? Colors.white.withValues(alpha: 0.14)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.event_busy_outlined, size: 20),
            const SizedBox(width: 8),
            Text(_isLoading ? S.loadingEvent : S.eventUnavailable),
          ],
        ),
      );
    }

    final color = _eventColor(event);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final foreground = widget.onDarkBackground ? Colors.white : AppColors.text;
    final secondary = widget.onDarkBackground
        ? Colors.white70
        : AppColors.secondaryText;
    final date = DateFormat('EEE, MMM d', locale).format(event.dateTime);
    final time = DateFormat.jm(locale).format(event.dateTime);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('shared-event-card-${event.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(event: event, color: color),
          ),
        ),
        child: Container(
          width: 250,
          decoration: BoxDecoration(
            color: widget.onDarkBackground
                ? Colors.white.withValues(alpha: 0.13)
                : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.onDarkBackground
                  ? Colors.white.withValues(alpha: 0.22)
                  : AppColors.divider,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: 112,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    EventCoverImage(
                      event: event,
                      color: color,
                      width: 250,
                      height: 112,
                      cacheWidth: 500,
                      cacheHeight: 224,
                    ),
                    Positioned(
                      left: 10,
                      bottom: 9,
                      child: DynamicContrastText(
                        '$date · $time',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // See the note on the shared post card: a forwarded event
                    // is exactly where its audience is least obvious.
                    Positioned(
                      right: 9,
                      top: 8,
                      child: ContentAudiencePill.onMedia(
                        key: ValueKey('content-audience-pill-${event.id}'),
                        audience: audienceForEvent(event),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: secondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: secondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

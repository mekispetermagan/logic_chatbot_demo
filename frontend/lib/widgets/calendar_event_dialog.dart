import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../api/calendar_api.dart';
import '../api/conversation_api.dart' show ApiException;
import '../controllers/calendar_controller.dart';
import '../models/calendar_event.dart';
import '../models/calendar_week.dart';
import 'calendar_colors.dart';

enum _Mode { details, edit, delete }

class CalendarEventDialog extends StatefulWidget {
  const CalendarEventDialog({
    super.key,
    required this.controller,
    this.event,
    this.initialStart,
  }) : assert(event != null || initialStart != null);
  final CalendarController controller;
  final CalendarEvent? event;
  final tz.TZDateTime? initialStart;

  @override
  State<CalendarEventDialog> createState() => _CalendarEventDialogState();
}

class _CalendarEventDialogState extends State<CalendarEventDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  late _Mode _mode;
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  int _importance = 0;
  bool _importanceSet = false;
  bool _busy = false;
  bool _unconfirmed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.event == null ? _Mode.edit : _Mode.details;
    _resetDraft();
  }

  void _resetDraft() {
    final event = widget.event;
    final start = event?.start ?? widget.initialStart!;
    final endMinutes = (start.hour * 60 + start.minute + 60).clamp(0, 1439);
    _date = DateTime(start.year, start.month, start.day);
    _start = TimeOfDay(hour: start.hour, minute: start.minute);
    _end = event == null
        ? TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60)
        : TimeOfDay(hour: event.end.hour, minute: event.end.minute);
    _title.text = event?.title ?? '';
    _description.text = event?.description ?? '';
    _location.text = event?.location ?? '';
    _importance = calendarImportance(event?.colorId);
    _importanceSet = false;
    _error = null;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  bool get _timesChanged {
    final event = widget.event;
    return event == null ||
        !sameCalendarDay(_date, event.start) ||
        _start.hour != event.start.hour ||
        _start.minute != event.start.minute ||
        _end.hour != event.end.hour ||
        _end.minute != event.end.minute;
  }

  tz.TZDateTime _resolve(TimeOfDay time) {
    final value = tz.TZDateTime(
      budapest,
      _date.year,
      _date.month,
      _date.day,
      time.hour,
      time.minute,
    );
    bool sameWall(DateTime candidate) =>
        sameCalendarDay(candidate, _date) &&
        candidate.hour == time.hour &&
        candidate.minute == time.minute;
    if (!sameWall(value)) {
      throw const FormatException(
        'This time does not exist because the clocks change. Choose another time.',
      );
    }
    if (sameWall(value.add(const Duration(hours: 1))) ||
        sameWall(value.subtract(const Duration(hours: 1)))) {
      throw const FormatException(
        'This time occurs twice because the clocks change. Choose a time outside the repeated hour.',
      );
    }
    return value;
  }

  Map<String, dynamic> _fields() {
    final event = widget.event;
    final fields = <String, dynamic>{};
    if (event == null || _title.text.trim() != event.title) {
      fields['summary'] = _title.text.trim();
    }
    if (event == null || _description.text != event.description) {
      fields['description'] = _description.text;
    }
    if (event == null || _location.text != event.location) {
      fields['location'] = _location.text;
    }
    if (event == null || _importanceSet) {
      fields['colorId'] = calendarImportanceColorId(_importance);
    }
    if (_timesChanged) {
      final start = _resolve(_start);
      final end = _resolve(_end);
      if (!end.isAfter(start)) {
        throw const FormatException('End must be after start on the same day.');
      }
      fields['start'] = {
        'dateTime': start.toIso8601String(),
        'timeZone': calendarTimeZone,
      };
      fields['end'] = {
        'dateTime': end.toIso8601String(),
        'timeZone': calendarTimeZone,
      };
    }
    return fields;
  }

  Future<void> _submit({bool deleting = false}) async {
    if (_busy || _unconfirmed) return;
    Map<String, dynamic> fields = {};
    if (!deleting) {
      if (!_form.currentState!.validate()) return;
      try {
        fields = _fields();
      } on FormatException catch (failure) {
        setState(() => _error = failure.message);
        return;
      }
      if (fields.isEmpty) {
        Navigator.pop(context);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (deleting) {
        await widget.controller.delete(widget.event!.id);
      } else {
        await widget.controller.save(id: widget.event?.id, fields: fields);
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (failure) {
      if (mounted) {
        setState(() {
          _unconfirmed =
              failure is CalendarWriteException && failure.outcomeUnknown;
          _error = _unconfirmed
              ? 'The change may have completed. Close this dialog and refresh the calendar before trying again.'
              : failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _pickTime(bool start) async {
    final value = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          _start = value;
        } else {
          _end = value;
        }
      });
    }
  }

  void _cancel() {
    if (_busy) return;
    if (_mode == _Mode.edit && widget.event != null && !_unconfirmed) {
      setState(() {
        _resetDraft();
        _mode = _Mode.details;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: switch (_mode) {
      _Mode.details => _details(),
      _Mode.edit => _editor(),
      _Mode.delete => _deleteConfirmation(),
    },
  );

  Widget _details() {
    final event = widget.event!;
    final editable = widget.controller.canEdit && !event.isRecurring;
    return AlertDialog(
      key: const ValueKey('calendar-event-details'),
      title: Row(
        children: [
          Expanded(
            child: Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Edit event',
            onPressed: editable
                ? () => setState(() => _mode = _Mode.edit)
                : null,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete event',
            onPressed: editable
                ? () => setState(() => _mode = _Mode.delete)
                : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${calendarWeekdays[event.start.weekday - 1]}, ${event.start.day} ${calendarMonths[event.start.month - 1]} ${event.start.year}',
            ),
            const SizedBox(height: 8),
            Text(
              '${calendarTime(event.start)}–${calendarTime(event.end)} · $calendarTimeZone',
            ),
            if (event.location.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Location'),
              SelectableText(event.location),
            ],
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Description'),
              SelectableText(event.description),
            ],
            const SizedBox(height: 16),
            _importanceLabel(calendarImportance(event.colorId)),
            if (event.isRecurring) ...[
              const SizedBox(height: 16),
              const Text('Recurring events are read-only in this editor.'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _editor() => AlertDialog(
    key: const ValueKey('calendar-event-editor'),
    title: Text(widget.event == null ? 'New event' : 'Edit event'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('calendar-title'),
              controller: _title,
              enabled: !_busy && !_unconfirmed,
              decoration: const InputDecoration(labelText: 'Title'),
              maxLength: 1024,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a title.'
                  : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('calendar-date'),
              onPressed: _busy || _unconfirmed ? null : _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                '${_date.day} ${calendarMonths[_date.month - 1]} ${_date.year}',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('calendar-start'),
                    onPressed: _busy || _unconfirmed
                        ? null
                        : () => _pickTime(true),
                    child: Text(
                      'Start ${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('calendar-end'),
                    onPressed: _busy || _unconfirmed
                        ? null
                        : () => _pickTime(false),
                    child: Text(
                      'End ${_end.hour.toString().padLeft(2, '0')}:${_end.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
              ],
            ),
            Text(
              calendarTimeZone,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('calendar-description'),
              controller: _description,
              enabled: !_busy && !_unconfirmed,
              decoration: const InputDecoration(labelText: 'Description'),
              minLines: 2,
              maxLines: 4,
              maxLength: 8192,
            ),
            TextFormField(
              key: const ValueKey('calendar-location'),
              controller: _location,
              enabled: !_busy && !_unconfirmed,
              decoration: const InputDecoration(labelText: 'Location'),
              maxLength: 1024,
            ),
            DropdownButtonFormField<int>(
              key: const ValueKey('calendar-importance'),
              initialValue: _importance,
              decoration: const InputDecoration(labelText: 'Importance'),
              isExpanded: true,
              items: [
                for (var level = 0; level <= 2; level++)
                  DropdownMenuItem(
                    value: level,
                    child: _importanceLabel(level),
                  ),
              ],
              onChanged: _busy || _unconfirmed
                  ? null
                  : (value) => setState(() {
                      _importance = value!;
                      _importanceSet = true;
                    }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : _cancel,
        child: Text(_unconfirmed ? 'Close' : 'Cancel'),
      ),
      FilledButton(
        onPressed: _busy || _unconfirmed ? null : () => _submit(),
        child: const Text('Save'),
      ),
    ],
  );

  Widget _deleteConfirmation() => AlertDialog(
    key: const ValueKey('calendar-delete-confirmation'),
    title: const Text('Delete event?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delete “${widget.event!.title}”?'),
        if (_error != null) ...[const SizedBox(height: 16), Text(_error!)],
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy
            ? null
            : () {
                if (_unconfirmed) {
                  Navigator.pop(context);
                } else {
                  setState(() {
                    _mode = _Mode.details;
                    _error = null;
                  });
                }
              },
        child: Text(_unconfirmed ? 'Close' : 'No'),
      ),
      FilledButton(
        onPressed: _busy || _unconfirmed ? null : () => _submit(deleting: true),
        child: const Text('Yes'),
      ),
    ],
  );

  Widget _importanceLabel(int level) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: calendarEventColor(calendarImportanceColorId(level)),
        ),
      ),
      const SizedBox(width: 8),
      Text(const ['Normal', 'Important', 'Critical'][level]),
    ],
  );
}

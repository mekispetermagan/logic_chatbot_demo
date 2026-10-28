import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import '../controllers/calendar_controller.dart';
import '../models/calendar_week.dart';

/// Calendar-specific review, clarification and recovery controls for ChatPanel.
class CalendarDialogueControls extends StatefulWidget {
  const CalendarDialogueControls({super.key, required this.controller});
  final CalendarController controller;

  @override
  State<CalendarDialogueControls> createState() =>
      _CalendarDialogueControlsState();
}

class _CalendarDialogueControlsState extends State<CalendarDialogueControls> {
  final _revision = TextEditingController();
  String? _parameter;
  CalendarController get controller => widget.controller;

  @override
  void dispose() {
    _revision.dispose();
    super.dispose();
  }

  String _field(String key, dynamic value) {
    if ((key == 'start' || key == 'end') && value is int) {
      return calendarDateTime(
        tz.TZDateTime.from(
          DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true),
          budapest,
        ),
      );
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final data = controller.dialogue;
    final status = controller.chatStatus;
    final busy = controller.chatBusy;
    final pending = controller.dialoguePending;
    final question = controller.pendingQuestion;
    final parameters = data?['parameters'] as Map? ?? {};
    final plan = data?['plan'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending && !const ['applying', 'recovery'].contains(status))
          const Text('Provisional evaluation · changes await acceptance'),
        if (question != null && status == 'clarify')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(question['prompt'] as String),
                  for (final option in question['options'] as List)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => controller.act({
                              'type': 'answer',
                              'key': question['key'],
                              'value': option[1],
                            }),
                      child: Text('${option[0]}'),
                    ),
                ],
              ),
            ),
          ),
        if (const ['review', 'prefix'].contains(status)) ...[
          Text(
            status == 'prefix'
                ? 'Successful prefix only; the remaining entry will not run.'
                : 'Review proposed changes',
          ),
          for (final operation in plan)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${operation['type']} #${operation['handle']}'),
                    for (final field in (operation['fields'] as Map).entries)
                      SelectableText(
                        '${field.key}: ${_field(field.key as String, field.value)}',
                      ),
                  ],
                ),
              ),
            ),
          if (plan.isEmpty)
            const Text(
              'No external field changes. Discourse may still change.',
            ),
          FilledButton(
            onPressed: busy ? null : () => controller.act({'type': 'accept'}),
            child: Text(
              status == 'prefix'
                  ? 'Accept successful prefix'
                  : 'Accept changes',
            ),
          ),
        ],
        if (data?['canRevise'] == true &&
            !const ['applying', 'recovery'].contains(status) &&
            parameters.isNotEmpty)
          ExpansionTile(
            title: const Text('Revise an established requirement'),
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: parameters.containsKey(_parameter)
                    ? _parameter
                    : null,
                items: [
                  for (final key in parameters.keys)
                    DropdownMenuItem(
                      value: key as String,
                      child: Text(
                        '$key: ${parameters[key]}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => _parameter = value),
              ),
              TextField(
                controller: _revision,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Replacement value (JSON number/list, or text)',
                ),
              ),
              TextButton(
                onPressed: busy || _parameter == null
                    ? null
                    : () => controller.reviseRequirement(
                        _parameter!,
                        _revision.text,
                      ),
                child: const Text('Revise and evaluate'),
              ),
            ],
          ),
        if (status == 'recovery' || status == 'applying') ...[
          const Text(
            'Cloud outcome needs verification. No automatic retry or rollback.',
          ),
          for (final item in data?['journal'] as List? ?? [])
            Text('${item['type']} #${item['handle']}: ${item['status']}'),
          TextButton(
            onPressed: busy
                ? null
                : () => controller.act({'type': 'reconcile'}),
            child: const Text('Reconcile (read only)'),
          ),
          TextButton(
            onPressed: busy ? null : () => controller.act({'type': 'continue'}),
            child: const Text('Authorize remaining writes'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => controller.act({'type': 'keepPartial'}),
            child: const Text('Keep verified partial result'),
          ),
        ],
        if (pending && !const ['applying', 'recovery'].contains(status))
          TextButton(
            onPressed: busy ? null : () => controller.act({'type': 'cancel'}),
            child: const Text('Cancel pending entry'),
          ),
      ],
    );
  }
}

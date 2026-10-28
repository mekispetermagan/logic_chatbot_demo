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
    if (controller.statusUncertain) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Refresh chat status before sending or approving another request.',
          ),
          TextButton(
            onPressed: controller.chatBusy ? null : controller.loadDialogue,
            child: const Text('Refresh chat status'),
          ),
        ],
      );
    }
    if (controller.otherChatPending) {
      return const Text(
        'The other Calendar chat has a pending task. Switch to it to finish or cancel that task.',
      );
    }
    if (controller.isLlmOnly) {
      return _LlmOnlyControls(controller: controller);
    }
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

/// Only the approval/recovery controls vary; history and composer stay shared.
class _LlmOnlyControls extends StatelessWidget {
  const _LlmOnlyControls({required this.controller});
  final CalendarController controller;

  String _operation(dynamic tool) => switch (tool) {
    'create-event' => 'Create event',
    'update-event' => 'Update event',
    'delete-event' => 'Delete event',
    _ => '$tool',
  };

  String _field(dynamic key) => switch (key) {
    'summary' => 'Title',
    'eventId' => 'Event ID',
    'colorId' => 'Color ID',
    'start' => 'Start',
    'end' => 'End',
    'timeZone' => 'Timezone',
    'location' => 'Location',
    'description' => 'Description',
    _ => '$key',
  };

  @override
  Widget build(BuildContext context) {
    final data = controller.dialogue ?? {};
    final status = controller.chatStatus;
    final busy = controller.chatBusy;
    final review = data['review'] as Map?;
    final journal = data['journal'] as List? ?? [];
    final canContinue = data['canContinue'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == 'clarification')
          const Text('Reply to the agent’s question to continue.'),
        if (status == 'review' && review != null) ...[
          const Text('Review proposed changes'),
          for (final operation in review['operations'] as List)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_operation(operation['tool'])),
                    for (final field in (operation['arguments'] as Map).entries)
                      if (!const [
                        'account',
                        'calendarId',
                        'sendUpdates',
                      ].contains(field.key))
                        SelectableText('${_field(field.key)}: ${field.value}'),
                  ],
                ),
              ),
            ),
          FilledButton(
            onPressed: busy
                ? null
                : () => controller.act({
                    'type': 'accept',
                    'proposalId': review['id'],
                  }),
            child: const Text('Accept changes'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => controller.act({
                    'type': 'reject',
                    'proposalId': review['id'],
                  }),
            child: const Text('Reject changes'),
          ),
        ],
        if (const ['running', 'suspended'].contains(status)) ...[
          const Text(
            'The agent turn needs inspection. Resume the existing turn; do not resend the request.',
          ),
          FilledButton(
            onPressed: busy ? null : () => controller.act({'type': 'resume'}),
            child: const Text('Resume agent turn'),
          ),
        ],
        if (const ['recovery', 'applying'].contains(status)) ...[
          const Text(
            'Cloud outcome needs verification. No automatic retry or rollback.',
          ),
          for (final item in journal)
            Text('${_operation(item['tool'])}: ${item['status']}'),
          TextButton(
            onPressed: busy
                ? null
                : () => controller.act({'type': 'reconcile'}),
            child: const Text('Reconcile (read only)'),
          ),
          TextButton(
            onPressed: busy || !canContinue
                ? null
                : () => controller.act({'type': 'continue'}),
            child: const Text('Authorize remaining writes'),
          ),
          TextButton(
            onPressed: busy || !canContinue
                ? null
                : () => controller.act({'type': 'keepPartial'}),
            child: const Text('Keep verified partial result'),
          ),
        ],
        if (controller.dialoguePending &&
            !const ['applying', 'recovery'].contains(status))
          TextButton(
            onPressed: busy ? null : () => controller.act({'type': 'cancel'}),
            child: const Text('Cancel pending entry'),
          ),
      ],
    );
  }
}

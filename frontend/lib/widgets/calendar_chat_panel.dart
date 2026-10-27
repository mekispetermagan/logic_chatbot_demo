import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import '../controllers/calendar_controller.dart';
import '../models/calendar_week.dart';
import '../models/chat_message.dart';
import 'chat_panel.dart';

class CalendarChatPanel extends StatefulWidget {
  const CalendarChatPanel({super.key, required this.controller});
  final CalendarController controller;
  @override
  State<CalendarChatPanel> createState() => _CalendarChatPanelState();
}

class _CalendarChatPanelState extends State<CalendarChatPanel> {
  final _revision = TextEditingController();
  String? _parameter;
  CalendarController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.loadDialogue();
    });
  }

  @override
  void dispose() {
    _revision.dispose();
    super.dispose();
  }

  dynamic _value(String text, [String? kind]) {
    if (const [
      'text',
      'date',
      'moment',
      'window',
      'condition',
      'clock',
    ].contains(kind)) {
      return text;
    }
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final data = controller.dialogue;
      final status = data?['status'] as String? ?? 'idle';
      final busy = controller.chatBusy;
      final pending = controller.dialoguePending;
      final question = data?['question'] as Map?;
      final parameters = data?['parameters'] as Map? ?? {};
      final messages = data?['messages'] as List? ?? [];
      final plan = data?['plan'] as List? ?? [];
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Calendar dialogue')),
                IconButton(
                  tooltip: 'Refresh dialogue status',
                  onPressed: busy ? null : controller.loadDialogue,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'Controlled English · selected-week scope · five-minute model',
              style: TextStyle(fontSize: 12),
            ),
            if (pending && !const ['applying', 'recovery'].contains(status))
              const Text('Provisional evaluation · changes await acceptance'),
            Expanded(
              child: ChatPanel(
                messages: [
                  for (final message in messages)
                    ChatMessage.fromJson(
                      Map<String, dynamic>.from(message as Map),
                    ),
                ],
                canSend: data != null && (!pending || status == 'clarify'),
                composerEnabled:
                    data != null && (!pending || status == 'clarify'),
                sending: busy,
                error: controller.chatError,
                onRefresh: controller.loadDialogue,
                composerKey: const ValueKey('calendar-entry'),
                composerHint: status == 'clarify'
                    ? 'Answer (${question?['kind']})'
                    : 'Controlled English entry',
                emptyHint:
                    'Try: Schedule event lasting 30 minutes within thursday morning.\n\nThe engine asks for missing information. Changes await acceptance.',
                onSend: (text) async {
                  await controller.act(
                    status == 'clarify' && question != null
                        ? {
                            'type': 'answer',
                            'key': question['key'],
                            'value': _value(text, question['kind'] as String?),
                          }
                        : {'type': 'start', 'text': text},
                  );
                  return controller.chatError == null;
                },
                controls: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                                Text(
                                  '${operation['type']} #${operation['handle']}',
                                ),
                                for (final field
                                    in (operation['fields'] as Map).entries)
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
                        onPressed: busy
                            ? null
                            : () => controller.act({'type': 'accept'}),
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
                              labelText:
                                  'Replacement value (JSON number/list, or text)',
                            ),
                          ),
                          TextButton(
                            onPressed: busy || _parameter == null
                                ? null
                                : () => controller.act({
                                    'type': 'revise',
                                    'key': _parameter,
                                    'value': _value(
                                      _revision.text,
                                      parameters[_parameter] is String
                                          ? 'text'
                                          : null,
                                    ),
                                  }),
                            child: const Text('Revise and evaluate'),
                          ),
                        ],
                      ),
                    if (status == 'recovery' || status == 'applying') ...[
                      const Text(
                        'Cloud outcome needs verification. No automatic retry or rollback.',
                      ),
                      for (final item in data?['journal'] as List? ?? [])
                        Text(
                          '${item['type']} #${item['handle']}: ${item['status']}',
                        ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => controller.act({'type': 'reconcile'}),
                        child: const Text('Reconcile (read only)'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => controller.act({'type': 'continue'}),
                        child: const Text('Authorize remaining writes'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => controller.act({'type': 'keepPartial'}),
                        child: const Text('Keep verified partial result'),
                      ),
                    ],
                    if (pending &&
                        !const ['applying', 'recovery'].contains(status))
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => controller.act({'type': 'cancel'}),
                        child: const Text('Cancel pending entry'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

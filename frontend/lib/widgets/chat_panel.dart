import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Owns only composer text; conversation state and requests stay in the controller.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.messages,
    required this.canSend,
    required this.sending,
    required this.onSend,
    required this.onRefresh,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool canSend;
  final bool sending;
  final String? error;
  final Future<bool> Function(String) onSend;
  final VoidCallback onRefresh;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _composer = TextEditingController();
  bool _submitting = false;

  Future<void> _send() async {
    if (_submitting || !widget.canSend || _composer.text.trim().isEmpty) return;
    final text = _composer.text;
    setState(() => _submitting = true);
    try {
      final accepted = await widget.onSend(text);
      if (mounted && accepted && _composer.text == text) _composer.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.sending || _submitting;
    return Column(
      children: [
        Expanded(
          child: widget.messages.isEmpty
              ? const Center(child: Text('Enter an atomic sentence to begin.'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, index) => ChatBubble(
                    message:
                        widget.messages[widget.messages.length - 1 - index],
                  ),
                ),
        ),
        if (widget.error != null) ...[
          Text(
            widget.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: widget.onRefresh,
            child: const Text('Refresh conversation'),
          ),
        ],
        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                enabled: !busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Enter a message',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _composer,
              builder: (context, value, child) => IconButton(
                tooltip: 'Send',
                onPressed:
                    widget.canSend && !busy && value.text.trim().isNotEmpty
                    ? _send
                    : null,
                icon: const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == ChatRole.user;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.9),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: user ? colors.primaryContainer : colors.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            border: message.isError ? Border.all(color: colors.error) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.isError
                    ? 'Engine · parse error'
                    : user
                    ? 'You'
                    : 'Engine',
                style: TextStyle(
                  fontSize: 12,
                  color: user
                      ? colors.onPrimaryContainer
                      : colors.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                message.text,
                style: TextStyle(
                  color: user
                      ? colors.onPrimaryContainer
                      : colors.onSecondaryContainer,
                  fontFamily: user ? null : 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

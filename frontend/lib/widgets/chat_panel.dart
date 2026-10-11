import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/world_object.dart';
import '../models/conversation_state.dart';

/// Owns composer text and recall state; conversation requests stay in the controller.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.messages,
    required this.canSend,
    required this.sending,
    required this.onSend,
    required this.onRefresh,
    this.error,
    this.pending,
    this.onChoose,
    this.onChooseSquare,
  });

  final List<ChatMessage> messages;
  final bool canSend;
  final bool sending;
  final String? error;
  final PendingEntry? pending;
  final ValueChanged<int>? onChoose;
  final ValueChanged<BoardPosition>? onChooseSquare;
  final Future<bool> Function(String) onSend;
  final VoidCallback onRefresh;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  bool _submitting = false;
  List<String>? _inputHistory;
  int _historyIndex = 0;
  TextEditingValue? _draft;

  KeyEventResult _navigateHistory(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyUpEvent ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        _submitting ||
        widget.sending ||
        widget.pending != null) {
      return KeyEventResult.ignored;
    }
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!up && event.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final value = _composer.value;
    if (value.selection.isValid && !value.selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final editable = _composerFocus.context
        ?.findAncestorStateOfType<EditableTextState>();
    final offset = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final renderedLine = editable?.renderEditable.getLineAtOffset(
      TextPosition(offset: offset),
    );
    final line = renderedLine != null && renderedLine.isValid
        ? renderedLine
        : null;
    final atBoundary = up
        ? (line?.start == 0 ||
              (line == null && !value.text.substring(0, offset).contains('\n')))
        : (line?.end == value.text.length ||
              (line == null && !value.text.substring(offset).contains('\n')));
    if (!atBoundary) return KeyEventResult.ignored;

    if (_inputHistory == null) {
      if (!up) return KeyEventResult.ignored;
      final history = widget.messages
          .where((message) => message.role == ChatRole.user)
          .map((message) => message.text)
          .toList();
      if (history.isEmpty) return KeyEventResult.ignored;
      _inputHistory = history;
      _historyIndex = history.length;
      _draft = value;
    }
    final history = _inputHistory!;
    _historyIndex = (_historyIndex + (up ? -1 : 1)).clamp(0, history.length);
    if (_historyIndex == history.length) {
      _composer.value = _draft!;
      _inputHistory = null;
      _draft = null;
    } else {
      final text = history[_historyIndex];
      _composer.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    return KeyEventResult.handled;
  }

  void _insertNewline() {
    if (_submitting || widget.sending) return;
    final value = _composer.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _composer.value = TextEditingValue(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  Future<void> _send() async {
    if (_submitting ||
        widget.sending ||
        !widget.canSend ||
        _composer.text.trim().isEmpty) {
      return;
    }
    final text = _composer.text;
    _inputHistory = null;
    _draft = null;
    setState(() => _submitting = true);
    try {
      final accepted = await widget.onSend(text);
      if (mounted && accepted && _composer.text == text) _composer.clear();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.canSend && !widget.sending) {
            _composerFocus.requestFocus();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.sending || _submitting;
    return Column(
      children: [
        Expanded(
          child: widget.messages.isEmpty
              ? const Center(child: Text('Enter a sentence to begin.'))
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
        if (widget.pending case final pending?) ...[
          Text(
            '${pending.squareChoices.isEmpty ? 'Which object?' : 'Which square?'} ${pending.sentence}',
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final square in pending.squareChoices)
                    OutlinedButton(
                      onPressed: busy || widget.onChooseSquare == null
                          ? null
                          : () => widget.onChooseSquare!(square),
                      child: Text(square.square),
                    ),
                  for (final candidate in pending.candidates)
                    OutlinedButton(
                      onPressed: busy || widget.onChoose == null
                          ? null
                          : () => widget.onChoose!(candidate.objectId),
                      child: Text(candidate.label),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
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
              child: Focus(
                onKeyEvent: _navigateHistory,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                      includeRepeats: false,
                    ): _insertNewline,
                    const SingleActivator(
                      LogicalKeyboardKey.numpadEnter,
                      shift: true,
                      includeRepeats: false,
                    ): _insertNewline,
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      includeRepeats: false,
                    ): _send,
                    const SingleActivator(
                      LogicalKeyboardKey.numpadEnter,
                      includeRepeats: false,
                    ): _send,
                  },
                  child: TextField(
                    controller: _composer,
                    focusNode: _composerFocus,
                    enabled: !busy && widget.pending == null,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    onEditingComplete: () {},
                    decoration: const InputDecoration(
                      hintText: 'Enter a message',
                      border: OutlineInputBorder(),
                    ),
                  ),
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

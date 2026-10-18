import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/world_object.dart';
import '../models/conversation_state.dart';
import '../models/llm_usage.dart';
import '../models/interpretation_proposal.dart';
import 'interpretation_review.dart';

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
    this.onChooseGrouping,
    this.llmBudget,
    this.proposal,
    this.preview,
    this.selectedInterpretationRank,
    this.canReview = false,
    this.onSelectInterpretation,
    this.onPreview,
    this.onAccept,
    this.onReject,
    this.onAnswer,
    this.languageVersion = 'unknown',
  });

  final List<ChatMessage> messages;
  final bool canSend;
  final bool sending;
  final String? error;
  final PendingEntry? pending;
  final ValueChanged<int>? onChoose;
  final ValueChanged<BoardPosition>? onChooseSquare;
  final ValueChanged<int>? onChooseGrouping;
  final Future<bool> Function(String) onSend;
  final VoidCallback onRefresh;
  final LlmBudget? llmBudget;
  final InterpretationProposal? proposal;
  final InterpretationPreview? preview;
  final int? selectedInterpretationRank;
  final bool canReview;
  final ValueChanged<int>? onSelectInterpretation;
  final Future<bool> Function()? onPreview;
  final Future<bool> Function()? onAccept;
  final Future<bool> Function()? onReject;
  final Future<bool> Function(String)? onAnswer;
  final String languageVersion;

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
  bool get _answering => widget.proposal?.canAnswer == true;
  bool get _staleProposal =>
      widget.proposal != null &&
      widget.proposal!.languageVersion != widget.languageVersion;
  bool get _canSubmit => widget.proposal == null
      ? widget.canSend
      : _answering &&
            !_staleProposal &&
            widget.canReview &&
            widget.onAnswer != null;

  KeyEventResult _navigateHistory(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyUpEvent ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        _submitting ||
        widget.sending ||
        widget.pending != null ||
        widget.proposal != null) {
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
        !_canSubmit ||
        _composer.text.trim().isEmpty) {
      return;
    }
    final text = _composer.text;
    _inputHistory = null;
    _draft = null;
    setState(() => _submitting = true);
    try {
      final accepted = await (_answering
          ? widget.onAnswer!(text)
          : widget.onSend(text));
      if (mounted && accepted && _composer.text == text) _composer.clear();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _canSubmit && !widget.sending) {
            _composerFocus.requestFocus();
          }
        });
      }
    }
  }

  Future<void> _rejectProposal() async {
    final original = widget.proposal?.originalText;
    if (_submitting ||
        widget.sending ||
        original == null ||
        widget.onReject == null) {
      return;
    }
    setState(() => _submitting = true);
    try {
      if (await widget.onReject!() && mounted) {
        _inputHistory = null;
        _draft = null;
        _composer.value = TextEditingValue(
          text: original,
          selection: TextSelection.collapsed(offset: original.length),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _composerFocus.requestFocus();
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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
          child: widget.messages.isEmpty && widget.proposal == null
              ? const Center(child: Text('Enter a sentence to begin.'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount:
                      widget.messages.length +
                      (widget.proposal == null ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (widget.proposal case final proposal?) {
                      if (index == 0) {
                        return InterpretationReview(
                          key: ValueKey(proposal.id),
                          proposal: proposal,
                          selectedRank: widget.selectedInterpretationRank,
                          enabled: widget.canReview && !busy,
                          onSelect: widget.onSelectInterpretation ?? (_) {},
                          onPreview: () {
                            widget.onPreview?.call();
                          },
                          onAccept: () {
                            widget.onAccept?.call();
                          },
                          onReject: _rejectProposal,
                          preview: widget.preview,
                          languageVersion: widget.languageVersion,
                        );
                      }
                      index -= 1;
                    }
                    return ChatBubble(
                      message:
                          widget.messages[widget.messages.length - 1 - index],
                    );
                  },
                ),
        ),
        if (widget.pending case final pending?) ...[
          if (pending.stagedWorld != null)
            const Text(
              'Atomic batch pending — the displayed staged world is provisional; nothing has been applied.',
            ),
          Text(
            '${pending.groupingChoices.isNotEmpty
                ? 'Which grouping?'
                : pending.squareChoices.isNotEmpty && pending.candidates.isNotEmpty
                ? 'Which referent: object or square?'
                : pending.squareChoices.isEmpty
                ? 'Which object?'
                : 'Which square?'} ${pending.sentence}',
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final candidate in pending.groupingChoices)
                    OutlinedButton(
                      onPressed: busy || widget.onChooseGrouping == null
                          ? null
                          : () =>
                                widget.onChooseGrouping!(candidate.groupingId),
                      child: Text(candidate.label),
                    ),
                  for (final square in pending.squareChoices)
                    OutlinedButton(
                      onPressed: busy || widget.onChooseSquare == null
                          ? null
                          : () => widget.onChooseSquare!(square),
                      child: Text(
                        pending.candidates.isEmpty
                            ? square.square
                            : 'Square ${square.square}',
                      ),
                    ),
                  for (final candidate in pending.candidates)
                    OutlinedButton(
                      onPressed: busy || widget.onChoose == null
                          ? null
                          : () => widget.onChoose!(candidate.objectId),
                      child: Text(
                        pending.squareChoices.isEmpty
                            ? candidate.label
                            : 'Object ${candidate.label}',
                      ),
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
        if (widget.llmBudget case final budget?) ...[
          Tooltip(
            message:
                'Estimated spend shared across all conversations and domains. '
                'Remaining: \$${budget.remainingUsd.toStringAsFixed(6)}. '
                'Uncertain requests retain their maximum reservation.',
            child: Text(
              'LLM: \$${budget.spentUsd.toStringAsFixed(6)} / '
              '\$${budget.limitUsd.toStringAsFixed(2)}'
              '${budget.reservedUsd > 0 ? ' · \$${budget.reservedUsd.toStringAsFixed(6)} reserved' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
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
                    enabled:
                        !busy &&
                        !_staleProposal &&
                        widget.pending == null &&
                        (widget.proposal == null || _answering),
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    onEditingComplete: () {},
                    decoration: InputDecoration(
                      hintText: _answering
                          ? 'Clarification or correction'
                          : 'Enter a message',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _composer,
              builder: (context, value, child) {
                final submit =
                    _canSubmit && !busy && value.text.trim().isNotEmpty
                    ? _send
                    : null;
                return _answering
                    ? FilledButton(
                        onPressed: submit,
                        child: const Text('Submit answer'),
                      )
                    : IconButton(
                        tooltip: 'Send',
                        onPressed: submit,
                        icon: const Icon(Icons.send),
                      );
              },
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
    final conversational = message.llm?.status == 'conversation';
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
                    : conversational
                    ? 'Assistant'
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
                  fontFamily: user || conversational ? null : 'monospace',
                ),
              ),
              if (message.llm case final usage?) ...[
                const SizedBox(height: 8),
                Tooltip(
                  message:
                      'Estimated token cost at configured Standard rates.\n'
                      '${usage.model} · ${usage.status}\n'
                      'Input: ${usage.inputTokens ?? 'unknown'} tokens; '
                      'output including reasoning: ${usage.outputTokens ?? 'unknown'} tokens.',
                  child: Text(
                    usage.costUsd != null
                        ? 'LLM cost: \$${usage.costUsd!.toStringAsFixed(6)}'
                        : usage.reservedUsd > 0
                        ? 'LLM cost unknown · \$${usage.reservedUsd.toStringAsFixed(6)} reserved'
                        : 'LLM cost: \$0.000000',
                    style: Theme.of(context).textTheme.bodySmall,
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

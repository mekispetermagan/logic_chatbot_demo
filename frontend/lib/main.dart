import 'models/domain.dart';
import 'package:flutter/material.dart';

import 'api/conversation_api.dart';
import 'api/calendar_api.dart';
import 'config/api_config.dart';
import 'controllers/conversation_controller.dart';
import 'controllers/calendar_controller.dart';
import 'storage/conversation_id_store.dart';
import 'widgets/conversation_world_panel.dart';
import 'widgets/chat_panel.dart';
import 'widgets/domain_selector.dart';
import 'widgets/calendar_week_view.dart';
import 'widgets/calendar_chat_panel.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Logic Chatbot Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: const DemoScreen(),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({
    super.key,
    this.createController,
    this.createCalendarController,
  });

  final ConversationController Function()? createController;
  final CalendarController Function()? createCalendarController;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  late final ConversationController _controller;
  late final CalendarController _calendar;
  bool _showCalendar = false;

  @override
  void initState() {
    super.initState();
    final baseUrl = ApiConfig.baseUrl;
    _controller =
        widget.createController?.call() ??
        ConversationController(
          api: ConversationApi(baseUrl: baseUrl),
          store: PreferencesConversationIdStore(baseUrl: baseUrl),
        );
    _controller.load();
    _calendar =
        widget.createCalendarController?.call() ??
        CalendarController(api: CalendarApi(baseUrl: baseUrl));
  }

  @override
  void dispose() {
    _controller.dispose();
    _calendar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _calendar]),
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final actionSpacing = constraints.maxWidth < 360 ? 2.0 : 12.0;
          final worldPanel = PanelFrame(
            child: ConversationWorldPanel(
              conversation: _controller.conversation,
              previewWorld:
                  _controller.preview?.pending?.stagedWorld ??
                  _controller.preview?.world ??
                  _controller.conversation?.pending?.stagedWorld,
              previewLabel:
                  _controller.preview == null &&
                      _controller.conversation?.pending?.stagedWorld != null
                  ? 'Provisional batch — not applied'
                  : 'Preview — not applied',
              loading: _controller.loading,
              editing: _controller.editing,
              error: _controller.error,
              onRetry: _controller.load,
              selectedProperty: _controller.selectedProperty,
              selectedNetworkShape: _controller.selectedNetworkShape,
              selectedNetworkColor: _controller.selectedNetworkColor,
              onNetworkShapeChanged: _controller.canManipulateObjects
                  ? _controller.selectNetworkShape
                  : null,
              onNetworkColorChanged: _controller.canManipulateObjects
                  ? _controller.selectNetworkColor
                  : null,
              selectedUnplacedObjectId: _controller.selectedUnplacedObjectId,
              onPropertyChanged: _controller.canManipulateObjects
                  ? _controller.selectProperty
                  : null,
              onUnplacedObjectSelected: _controller.canManipulateObjects
                  ? _controller.selectUnplacedObject
                  : null,
              onPaint: _controller.canManipulateObjects
                  ? _controller.paint
                  : null,
              onErase: _controller.canManipulateObjects
                  ? _controller.erase
                  : null,
              onClear: _controller.canManipulateObjects
                  ? _controller.clear
                  : null,
              onStep: _controller.canStep ? _controller.step : null,
              onRulesetSubmitted: _controller.canEditCells
                  ? _controller.replaceRuleset
                  : null,
              selectedCellColor: _controller.selectedCellColor,
              onCellColorChanged: _controller.canEditCells
                  ? _controller.selectCellColor
                  : null,
              onPaintCell: _controller.canEditCells
                  ? _controller.paintCell
                  : null,
              onSaveSlot: _controller.canEdit
                  ? (slot, overwrite) =>
                        _controller.saveWorldSlot(slot, overwrite: overwrite)
                  : null,
              onLoadSlot: _controller.canEdit
                  ? _controller.loadWorldSlot
                  : null,
            ),
          );

          final chatPanel = PanelFrame(
            child: ChatPanel(
              key: ValueKey((_controller.domain, _controller.conversation?.id)),
              messages: _controller.conversation?.messages ?? const [],
              llmBudget: _controller.conversation?.llmBudget,
              canSend: _controller.canChat,
              emptyHint: _controller.domain == WorldDomain.cellular
                  ? 'Edit cells, change rules, or ask about future generations.'
                  : 'Enter a sentence to begin.',
              composerHint: 'Enter a message',
              loadExamples: () => _controller.api.examples(_controller.domain),
              canSendControl: _controller.canRequest
                  ? _controller.canSendControl
                  : null,
              resetPending: _controller.conversation?.resetPending == true,
              pending: _controller.conversation?.pending,
              proposal: _controller.conversation?.proposal,
              preview: _controller.preview,
              selectedInterpretationRank:
                  _controller.selectedInterpretationRank,
              canReview: _controller.canReview,
              languageVersion:
                  _controller.conversation?.languageVersion ?? 'unknown',
              onSelectInterpretation: _controller.selectInterpretation,
              onPreview: _controller.previewInterpretation,
              onAccept: _controller.acceptInterpretation,
              onReject: _controller.rejectInterpretation,
              onAnswer: _controller.answerInterpretation,
              onChoose: _controller.canClarify ? _controller.clarify : null,
              onChooseGrouping: _controller.canClarify
                  ? _controller.clarifyGrouping
                  : null,
              onChooseSquare: _controller.canClarify
                  ? _controller.clarifySquare
                  : null,
              sending: _controller.sendingChat,
              error: _controller.error,
              onSend: _controller.sendChat,
              onRefresh: _controller.load,
            ),
          );

          final displayedWorldPanel = _showCalendar
              ? PanelFrame(child: CalendarWeekView(controller: _calendar))
              : worldPanel;
          final displayedChatPanel = _showCalendar
              ? PanelFrame(
                  child: CalendarChatPanel(
                    key: ValueKey(_calendar.chatMode),
                    controller: _calendar,
                  ),
                )
              : chatPanel;

          return DefaultTabController(
            key: ValueKey(_showCalendar),
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: constraints.maxWidth >= 1400
                    ? const Text('Logic Chatbot Demo')
                    : null,
                actions: [
                  Padding(
                    padding: EdgeInsets.only(right: actionSpacing),
                    child: DomainSelector(
                      selected: _controller.domain,
                      compact: constraints.maxWidth < 950,
                      calendarSelected: _showCalendar && !_calendar.isLlmOnly,
                      calendarLlmOnlySelected:
                          _showCalendar && _calendar.isLlmOnly,
                      onCalendarSelected: () {
                        if (!_calendar.canSwitchChatMode) return;
                        setState(() => _showCalendar = true);
                        _calendar.selectChatMode(CalendarChatMode.symbolic);
                        _calendar.load();
                      },
                      onCalendarLlmOnlySelected: () {
                        if (!_calendar.canSwitchChatMode) return;
                        setState(() => _showCalendar = true);
                        _calendar.selectChatMode(CalendarChatMode.llmOnly);
                      },
                      onChanged:
                          _controller.canSwitchDomain &&
                              (!_showCalendar || _calendar.canSwitchChatMode)
                          ? (domain) {
                              setState(() => _showCalendar = false);
                              _controller.switchDomain(domain);
                            }
                          : null,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: actionSpacing),
                    child: Tooltip(
                      message: _showCalendar && _calendar.isLlmOnly
                          ? 'LLM-only Calendar always uses the agent'
                          : _controller.llmAvailable
                          ? 'Activate LLM: propose interpretations after a syntax error'
                          : 'Cellular dialogue is not available yet',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (wide) const Text('LLM'),
                          Switch(
                            padding: EdgeInsets.zero,
                            value: _showCalendar
                                ? (_calendar.isLlmOnly || _calendar.useLlm)
                                : _controller.llmEnabled,
                            onChanged: _showCalendar
                                ? (_calendar.canToggleLlm
                                      ? _calendar.setUseLlm
                                      : null)
                                : _controller.canSwitchDomain &&
                                      _controller.llmAvailable
                                ? _controller.setUseLlm
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_showCalendar)
                    Padding(
                      padding: EdgeInsets.only(right: actionSpacing),
                      child: IconButton(
                        tooltip: 'Undo',
                        onPressed: _controller.canUndo
                            ? _controller.undo
                            : null,
                        icon: const Icon(Icons.undo),
                      ),
                    ),
                ],
                bottom: wide
                    ? null
                    : const TabBar(
                        tabs: [
                          Tab(text: 'World'),
                          Tab(text: 'Chat'),
                        ],
                      ),
              ),
              body: SafeArea(
                child: wide
                    ? Row(
                        children: [
                          Expanded(child: displayedWorldPanel),
                          Expanded(child: displayedChatPanel),
                        ],
                      )
                    : TabBarView(
                        children: [displayedWorldPanel, displayedChatPanel],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PanelFrame extends StatelessWidget {
  const PanelFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

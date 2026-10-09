import 'package:flutter/material.dart';

import 'api/conversation_api.dart';
import 'config/api_config.dart';
import 'controllers/conversation_controller.dart';
import 'storage/conversation_id_store.dart';
import 'widgets/conversation_world_panel.dart';
import 'widgets/chat_panel.dart';

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
  const DemoScreen({super.key, this.createController});

  final ConversationController Function()? createController;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  late final ConversationController _controller;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final worldPanel = PanelFrame(
            child: ConversationWorldPanel(
              conversation: _controller.conversation,
              loading: _controller.loading,
              editing: _controller.editing,
              error: _controller.error,
              onRetry: _controller.load,
              selectedProperty: _controller.selectedProperty,
              selectedUnplacedObjectId: _controller.selectedUnplacedObjectId,
              onPropertyChanged: _controller.canEdit
                  ? _controller.selectProperty
                  : null,
              onUnplacedObjectSelected: _controller.canEdit
                  ? _controller.selectUnplacedObject
                  : null,
              onPaint: _controller.canEdit ? _controller.paint : null,
              onErase: _controller.canEdit ? _controller.erase : null,
              onClear: _controller.canEdit ? _controller.clear : null,
            ),
          );

          final chatPanel = PanelFrame(
            child: ChatPanel(
              messages: _controller.conversation?.messages ?? const [],
              canSend: _controller.canEdit,
              pending: _controller.conversation?.pending,
              onChoose: _controller.canRequest ? _controller.clarify : null,
              sending: _controller.sendingChat,
              error: _controller.error,
              onSend: _controller.sendChat,
              onRefresh: _controller.load,
            ),
          );

          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Logic Chatbot Demo'),
                actions: [
                  IconButton(
                    tooltip: 'Undo',
                    onPressed:
                        _controller.canRequest &&
                            _controller.conversation?.canUndo == true
                        ? _controller.undo
                        : null,
                    icon: const Icon(Icons.undo),
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
                          Expanded(child: worldPanel),
                          Expanded(child: chatPanel),
                        ],
                      )
                    : TabBarView(children: [worldPanel, chatPanel]),
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

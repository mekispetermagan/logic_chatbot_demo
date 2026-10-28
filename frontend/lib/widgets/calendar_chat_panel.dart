import 'package:flutter/material.dart';
import '../controllers/calendar_controller.dart';
import 'calendar_dialogue_controls.dart';
import 'chat_panel.dart';

/// Binds Calendar state and actions to the same chat presentation as every domain.
class CalendarChatPanel extends StatelessWidget {
  const CalendarChatPanel({super.key, required this.controller});
  final CalendarController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ChatPanel(
      messages: controller.chatMessages,
      canSend: controller.canChat,
      composerEnabled: controller.canChat,
      answering: controller.awaitingAnswer,
      proposal: controller.proposal,
      preview: controller.preview,
      selectedInterpretationRank: controller.selectedInterpretationRank,
      canReview: controller.canReview,
      languageVersion: 'calendar-v1',
      llmBudget: controller.llmBudget,
      onSelectInterpretation: controller.selectInterpretation,
      onPreview: controller.previewInterpretation,
      onAccept: controller.acceptInterpretation,
      onReject: controller.rejectInterpretation,
      sending: controller.chatBusy,
      error: controller.chatError,
      onRefresh: controller.loadDialogue,
      loadExamples: controller.api.examples,
      composerKey: const ValueKey('calendar-entry'),
      onSend: controller.sendChat,
      onAnswer: controller.proposal != null
          ? controller.answerInterpretation
          : controller.sendChat,
      controls: controller.hasDialogueControls
          ? CalendarDialogueControls(controller: controller)
          : null,
    ),
  );
}

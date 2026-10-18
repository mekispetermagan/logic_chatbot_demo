import 'package:flutter/material.dart';

import '../models/interpretation_proposal.dart';

class InterpretationReview extends StatelessWidget {
  const InterpretationReview({
    super.key,
    required this.proposal,
    required this.selectedRank,
    required this.enabled,
    required this.onSelect,
    required this.onPreview,
    required this.onAccept,
    required this.onReject,
    this.preview,
    this.languageVersion = 'unknown',
  });

  final InterpretationProposal proposal;
  final int? selectedRank;
  final bool enabled;
  final ValueChanged<int> onSelect;
  final VoidCallback onPreview;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final InterpretationPreview? preview;
  final String languageVersion;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stale = proposal.languageVersion != languageVersion;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              proposal.candidates.isNotEmpty
                  ? 'Review interpretation'
                  : proposal.validationFailures.isNotEmpty
                  ? 'Translation failed validation'
                  : proposal.question.isNotEmpty
                  ? 'Clarification needed'
                  : 'No valid translation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (stale)
              const Text(
                'This interpretation uses an older language version. Reject it and resend your prompt.',
              ),
            if (proposal.question.isNotEmpty) ...[
              SelectableText(
                proposal.question,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ],
            if (proposal.explanation.isNotEmpty) ...[
              SelectableText(proposal.explanation),
              const SizedBox(height: 8),
            ],
            if (proposal.candidates.length > 1)
              const Text(
                'Ranked from most to least plausible. Choose a reading.',
              ),
            for (final failure in proposal.validationFailures) ...[
              SelectableText(
                'Discarded translation: ${failure.reason}',
                style: TextStyle(color: colors.error),
              ),
              ExpansionTile(
                title: Text(
                  failure.interpretation.isEmpty
                      ? 'Invalid controlled English'
                      : failure.interpretation,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  SelectableText(
                    failure.translation,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
            for (final candidate in proposal.candidates)
              Card(
                color: candidate.rank == selectedRank
                    ? colors.secondaryContainer
                    : null,
                child: Column(
                  children: [
                    Semantics(
                      selected: candidate.rank == selectedRank,
                      child: ListTile(
                        key: ValueKey('interpretation-${candidate.rank}'),
                        leading: Icon(
                          candidate.rank == selectedRank
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(
                          '${candidate.rank}. ${candidate.interpretation}',
                        ),
                        subtitle: candidate.explanation.isEmpty
                            ? null
                            : Text(candidate.explanation),
                        onTap: enabled ? () => onSelect(candidate.rank) : null,
                      ),
                    ),
                    ExpansionTile(
                      initiallyExpanded: candidate.rank == 1,
                      title: const Text('Controlled English'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          candidate.translation,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: enabled && !stale && selectedRank != null
                      ? onPreview
                      : null,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview'),
                ),
                FilledButton.icon(
                  onPressed: enabled && !stale && selectedRank != null
                      ? onAccept
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Accept'),
                ),
                OutlinedButton.icon(
                  onPressed: enabled ? onReject : null,
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              proposal.canAnswer
                  ? 'Reply below and submit your answer for another LLM interpretation, or reject to edit the original prompt. Nothing is applied until you accept.'
                  : 'Nothing is applied until you accept. Reject to revise your prompt.',
            ),
            if (preview case final result?) ...[
              const SizedBox(height: 12),
              const Text(
                'Preview — not applied',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (result.pending != null)
                const Text(
                  'The engine will ask for an object or square clarification after acceptance.',
                ),
              if (result.pending?.stagedWorld != null)
                const Text(
                  'This board is a provisional atomic-batch preview; none of its changes are committed.',
                ),
              if (result.changes.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Identity and state changes',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final change in result.changes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (change.kind) {
                      'position' => Icons.open_with,
                      'created' => Icons.add_circle_outline,
                      'deleted' => Icons.remove_circle_outline,
                      _ => Icons.palette_outlined,
                    }),
                    title: Text(change.detail),
                  ),
              ],
              SelectableText(
                result.feedback,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

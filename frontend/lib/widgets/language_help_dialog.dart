import 'package:flutter/material.dart';
import '../api/conversation_api.dart' show ApiException;
import '../models/language_examples.dart';

class LanguageHelpDialog extends StatefulWidget {
  const LanguageHelpDialog({super.key, required this.loadExamples});
  final Future<LanguageExamples> Function() loadExamples;

  @override
  State<LanguageHelpDialog> createState() => _LanguageHelpDialogState();
}

class _LanguageHelpDialogState extends State<LanguageHelpDialog> {
  late Future<LanguageExamples> _examples;

  @override
  void initState() {
    super.initState();
    _examples = widget.loadExamples();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 720,
      height: 600,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Controlled English examples',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
                IconButton(
                  tooltip: 'Close examples',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<LanguageExamples>(
              future: _examples,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            error is ApiException
                                ? error.message
                                : 'Could not load language examples.',
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _examples = widget.loadExamples();
                            }),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  key: const ValueKey('language-examples-list'),
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      '${data.domain} · ${data.languageVersion}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    for (final section in data.sections) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 8),
                        child: Text(
                          section.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final example in section.examples)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: SelectableText.rich(
                            TextSpan(
                              children: [
                                for (final segment in example)
                                  TextSpan(
                                    text: segment.text,
                                    style: segment.reference
                                        ? TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          )
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

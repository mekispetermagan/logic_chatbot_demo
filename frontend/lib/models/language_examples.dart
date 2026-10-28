class LanguageExamples {
  const LanguageExamples({
    required this.domain,
    required this.languageVersion,
    required this.sections,
  });

  factory LanguageExamples.fromJson(Map<String, dynamic> json) =>
      LanguageExamples(
        domain: json['domain'] as String,
        languageVersion: json['languageVersion'] as String,
        sections: [
          for (final section in json['sections'] as List)
            ExampleSection(
              title: section['title'] as String,
              examples: [
                for (final example in section['examples'] as List)
                  [
                    for (final segment in example as List)
                      ExampleSegment.fromJson(segment as Map<String, dynamic>),
                  ],
              ],
            ),
        ],
      );

  final String domain;
  final String languageVersion;
  final List<ExampleSection> sections;
}

class ExampleSection {
  const ExampleSection({required this.title, required this.examples});
  final String title;
  final List<List<ExampleSegment>> examples;
}

class ExampleSegment {
  const ExampleSegment({required this.text, this.reference = false});

  factory ExampleSegment.fromJson(Map<String, dynamic> json) => ExampleSegment(
    text: json['text'] as String,
    reference: json['reference'] as bool? ?? false,
  );

  final String text;
  final bool reference;
}

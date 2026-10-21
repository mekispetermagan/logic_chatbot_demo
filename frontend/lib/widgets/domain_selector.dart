import 'package:flutter/material.dart';

import '../models/domain.dart';

class DomainSelector extends StatelessWidget {
  const DomainSelector({
    super.key,
    required this.selected,
    required this.compact,
    this.onChanged,
  });

  final WorldDomain selected;
  final bool compact;
  final ValueChanged<WorldDomain>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return DropdownButtonHideUnderline(
        child: DropdownButton<WorldDomain>(
          key: const ValueKey('domain-selector'),
          value: selected,
          isDense: true,
          items: [
            for (final domain in WorldDomain.values)
              DropdownMenuItem(value: domain, child: Text(domain.label)),
          ],
          onChanged: onChanged == null
              ? null
              : (domain) {
                  if (domain != null) onChanged!(domain);
                },
        ),
      );
    }
    return SegmentedButton<WorldDomain>(
      key: const ValueKey('domain-selector'),
      segments: [
        for (final domain in WorldDomain.values)
          ButtonSegment(value: domain, label: Text(domain.label)),
      ],
      selected: {selected},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
        minimumSize: WidgetStatePropertyAll(Size(0, 36)),
      ),
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged!(selection.single),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/domain.dart';

enum _View {
  objects('Objects'),
  network('Network'),
  cellular('Cellular'),
  calendar('Calendar'),
  calendarLlmOnly('Calendar · LLM-only');

  const _View(this.label);
  final String label;
}

class DomainSelector extends StatelessWidget {
  const DomainSelector({
    super.key,
    required this.selected,
    required this.compact,
    this.onChanged,
    this.calendarSelected = false,
    this.onCalendarSelected,
    this.calendarLlmOnlySelected = false,
    this.onCalendarLlmOnlySelected,
  });

  final WorldDomain selected;
  final bool compact;
  final ValueChanged<WorldDomain>? onChanged;
  final bool calendarSelected;
  final bool calendarLlmOnlySelected;
  final VoidCallback? onCalendarLlmOnlySelected;
  final VoidCallback? onCalendarSelected;

  @override
  Widget build(BuildContext context) {
    final current = calendarLlmOnlySelected
        ? _View.calendarLlmOnly
        : calendarSelected
        ? _View.calendar
        : _View.values.byName(selected.name);
    void choose(_View view) {
      if (view == _View.calendarLlmOnly) {
        onCalendarLlmOnlySelected?.call();
      } else if (view == _View.calendar) {
        onCalendarSelected?.call();
      } else {
        onChanged?.call(WorldDomain.values.byName(view.name));
      }
    }

    if (compact) {
      return DropdownButtonHideUnderline(
        child: SizedBox(
          width: 150,
          child: DropdownButton<_View>(
            isExpanded: true,
            key: const ValueKey('domain-selector'),
            value: current,
            isDense: true,
            items: [
              for (final view in _View.values)
                DropdownMenuItem(
                  value: view,
                  child: Text(view.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged == null
                ? null
                : (view) {
                    if (view != null) choose(view);
                  },
          ),
        ),
      );
    }
    return SizedBox(
      width: 700,
      child: SegmentedButton<_View>(
        key: const ValueKey('domain-selector'),
        segments: [
          for (final view in _View.values)
            ButtonSegment(value: view, label: Text(view.label)),
        ],
        selected: {current},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
          minimumSize: WidgetStatePropertyAll(Size(0, 36)),
        ),
        onSelectionChanged: onChanged == null
            ? null
            : (selection) => choose(selection.single),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Google colors encode importance; all other or absent IDs mean level zero.
int calendarImportance(String? id) => switch (id) {
  '11' => 2,
  '5' => 1,
  _ => 0,
};

String calendarImportanceColorId(int importance) => switch (importance) {
  2 => '11',
  1 => '5',
  0 => '10',
  _ => throw ArgumentError.value(importance, 'importance'),
};

Color calendarEventColor(String? id) => switch (calendarImportance(id)) {
  2 => const Color(0xffd50000),
  1 => const Color(0xfff6bf26),
  _ => const Color(0xff0b8043),
};

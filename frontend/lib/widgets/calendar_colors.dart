import 'package:flutter/material.dart';

const calendarColors = <String, (String, Color)>{
  '1': ('Lavender', Color(0xff7986cb)),
  '2': ('Sage', Color(0xff33b679)),
  '3': ('Grape', Color(0xff8e24aa)),
  '4': ('Flamingo', Color(0xffe67c73)),
  '5': ('Banana', Color(0xfff6bf26)),
  '6': ('Tangerine', Color(0xfff4511e)),
  '7': ('Peacock', Color(0xff039be5)),
  '8': ('Graphite', Color(0xff616161)),
  '9': ('Blueberry', Color(0xff3f51b5)),
  '10': ('Basil', Color(0xff0b8043)),
  '11': ('Tomato', Color(0xffd50000)),
};

Color calendarEventColor(String? id) =>
    calendarColors[id]?.$2 ?? const Color(0xff4285f4);

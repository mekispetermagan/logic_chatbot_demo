class WorldSlot {
  const WorldSlot({required this.slot, this.savedAt});

  factory WorldSlot.fromJson(Map<String, dynamic> json) {
    final slot = json['slot'] as int;
    if (slot < 1 || slot > 5) throw const FormatException('Invalid world slot');
    return WorldSlot(slot: slot, savedAt: json['savedAt'] as String?);
  }

  final int slot;
  final String? savedAt;
  bool get isSaved => savedAt != null;
}

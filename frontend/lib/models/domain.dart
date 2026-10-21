/// Domain selection belongs to a conversation, not an undoable world snapshot.
enum WorldDomain {
  objects,
  network,
  cellular;

  String get label => switch (this) {
    objects => 'Objects',
    network => 'Network',
    cellular => 'Cellular',
  };
}

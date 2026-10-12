/// Canonical attribute/value pair sent to the logic engine for assignment.
class AttributeProperty {
  const AttributeProperty(this.attribute, this.value);

  final String attribute;
  final String value;

  Map<String, String> toJson() => {'attribute': attribute, 'value': value};
}

enum NetworkPort {
  north,
  east,
  south,
  west;

  AttributeProperty get property => AttributeProperty(name, name);
}

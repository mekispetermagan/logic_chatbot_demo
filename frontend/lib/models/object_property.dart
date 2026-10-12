import 'attribute_property.dart';
import 'world_object.dart';

/// The single base property supplied by a visual-editor performative.
enum ObjectProperty {
  red,
  blue,
  green,
  yellow,
  small,
  medium,
  large,
  bloom,
  spark,
  drop,
  loop;

  AttributeProperty get property => AttributeProperty(switch (this) {
    red || blue || green || yellow => 'color',
    small || medium || large => 'size',
    bloom || spark || drop || loop => 'shape',
  }, name);

  WorldObject applyTo(WorldObject object) => object.withProperty(property);
}

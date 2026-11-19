import 'package:flashco/models/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'all legacy scheme variants keep their names, order and JSON values',
    () {
      const legacyNames = [
        'tonalSpot',
        'fidelity',
        'monochrome',
        'neutral',
        'vibrant',
        'expressive',
        'content',
        'rainbow',
        'fruitSalad',
      ];
      expect(
        DynamicSchemeVariant.values.map((value) => value.name),
        legacyNames,
      );
      for (final name in legacyNames) {
        final theme = ThemeProps.fromJson({'schemeVariant': name});
        expect(theme.schemeVariant.name, name);
        expect(theme.toJson()['schemeVariant'], name);
      }
      expect(
        ThemeProps.fromJson({}).schemeVariant,
        DynamicSchemeVariant.content,
      );
    },
  );
}

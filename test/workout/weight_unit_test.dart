import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/weight_unit.dart';

/// The pure conversion/display type behind the live session's KG/LB switch.
/// Kilograms are canonical; pounds are a presentation/input skin over them.
void main() {
  group('conversion — accurate, not the rough 2.2', () {
    test('the exact factor round-trips 1 kg ↔ 1 lb-of-a-kg', () {
      // 1 kg is exactly WeightUnit.lbPerKg pounds, and back.
      expect(WeightUnit.lb.fromKg(1), closeTo(2.2046226218, 1e-9));
      expect(WeightUnit.lb.toKg(2.2046226218), closeTo(1, 1e-9));
    });

    test('the brief spec example: 190 lb entered stores ~86.18 kg', () {
      expect(WeightUnit.lb.toKg(190), closeTo(86.1826, 1e-3));
    });

    test('kg is the identity on both directions', () {
      expect(WeightUnit.kg.toKg(72.5), 72.5);
      expect(WeightUnit.kg.fromKg(72.5), 72.5);
    });
  });

  group('display — gym-friendly precision', () {
    test('kg keeps a single decimal, no trailing .0 (unchanged from before)', () {
      expect(WeightUnit.kg.display(60), '60');
      expect(WeightUnit.kg.display(72.5), '72.5');
    });

    test('lb snaps to the nearest half-pound so a conversion reads clean', () {
      // 86.18 kg → 189.99… lb → "190", not "189.998".
      expect(WeightUnit.lb.display(86.18), '190');
      // 72.5 kg → 159.83 lb → "160".
      expect(WeightUnit.lb.display(72.5), '160');
    });

    test('an lb display round-trips back through the field within its 0.5 grid', () {
      final kg = WeightUnit.lb.toKg(190); // what typing "190 lb" stores
      expect(WeightUnit.lb.display(kg), '190');
    });
  });

  group('step — equipment-aware, never a hardcoded 2.5', () {
    test('compound vs isolation, per unit', () {
      expect(WeightUnit.kg.step(small: false), 2.5);
      expect(WeightUnit.kg.step(small: true), 1.0);
      expect(WeightUnit.lb.step(small: false), 5.0);
      expect(WeightUnit.lb.step(small: true), 2.5);
    });

    test('weightStepFor keys off the muscle group like the progression engine', () {
      expect(weightStepFor(WeightUnit.kg, 'Chest'), 2.5);
      expect(weightStepFor(WeightUnit.kg, 'Biceps'), 1.0);
      expect(weightStepFor(WeightUnit.lb, 'Back'), 5.0);
      expect(weightStepFor(WeightUnit.lb, 'Rear delts'), 2.5);
    });
  });

  group('symbols and persistence', () {
    test('latin symbols in both cases', () {
      expect(WeightUnit.kg.symbol, 'kg');
      expect(WeightUnit.kg.symbolCaps, 'KG');
      expect(WeightUnit.lb.symbol, 'lb');
      expect(WeightUnit.lb.symbolCaps, 'LB');
    });

    test('fromName round-trips and defaults to kg for the unknown', () {
      expect(WeightUnit.fromName('lb'), WeightUnit.lb);
      expect(WeightUnit.fromName('kg'), WeightUnit.kg);
      expect(WeightUnit.fromName(null), WeightUnit.kg);
      expect(WeightUnit.fromName('stone'), WeightUnit.kg);
    });
  });
}

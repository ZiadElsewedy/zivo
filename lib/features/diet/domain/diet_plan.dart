import 'diet_day.dart';
import 'diet_plan_status.dart';
import 'diet_source.dart';

/// The user's diet plan — a set of [DietDay]s, each with its own [Meal]s and
/// [FoodItem]s, structured (not a text note) so it can drive "what's today"
/// and "what's left" and, later, be populated by a PDF extractor.
class DietPlan {
  const DietPlan({
    required this.id,
    required this.name,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.days,
  });

  final String id;
  final String name; // 'Cut — 2200 kcal'
  final DietPlanStatus status;
  final DietSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DietDay> days;

  DietPlan copyWith({
    String? name,
    DietPlanStatus? status,
    List<DietDay>? days,
    DateTime? updatedAt,
  }) => DietPlan(
    id: id,
    name: name ?? this.name,
    status: status ?? this.status,
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    days: days ?? this.days,
  );
}

import 'university_item_type.dart';

/// A single academic obligation — an assignment or exam. Deliberately
/// lightweight: no separate Course entity, no grades, no timetables.
class UniversityItem {
  const UniversityItem({
    required this.id,
    required this.title,
    required this.type,
    required this.createdAt,
    this.due,
    this.courseName,
    this.done = false,
  });

  final String id;
  final String title;
  final UniversityItemType type;
  final DateTime createdAt;
  final DateTime? due;
  final String? courseName;
  final bool done;

  UniversityItem copyWith({
    String? title,
    UniversityItemType? type,
    DateTime? due,
    bool clearDue = false,
    String? courseName,
    bool clearCourseName = false,
    bool? done,
  }) => UniversityItem(
    id: id,
    title: title ?? this.title,
    type: type ?? this.type,
    createdAt: createdAt,
    due: clearDue ? null : (due ?? this.due),
    courseName: clearCourseName ? null : (courseName ?? this.courseName),
    done: done ?? this.done,
  );
}

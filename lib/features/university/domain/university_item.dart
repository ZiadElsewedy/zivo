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

  UniversityItem copyWith({bool? done}) => UniversityItem(
    id: id,
    title: title,
    type: type,
    createdAt: createdAt,
    due: due,
    courseName: courseName,
    done: done ?? this.done,
  );
}

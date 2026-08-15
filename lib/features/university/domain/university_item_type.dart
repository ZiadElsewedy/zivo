/// The kind of a [UniversityItem] — an assignment to submit, or an exam to sit.
enum UniversityItemType { assignment, exam }

extension UniversityItemTypeLabel on UniversityItemType {
  String get label => switch (this) {
    UniversityItemType.assignment => 'Assignment',
    UniversityItemType.exam => 'Exam',
  };
}

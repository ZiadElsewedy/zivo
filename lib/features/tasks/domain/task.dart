/// A lightweight personal to-do — a state entity ("what is true now").
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.createdAt,
    this.due,
    this.priority = false,
    this.done = false,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime? due;
  final bool priority;
  final bool done;

  Task copyWith({
    String? title,
    DateTime? due,
    bool clearDue = false,
    bool? priority,
    bool? done,
  }) => Task(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        due: clearDue ? null : (due ?? this.due),
        priority: priority ?? this.priority,
        done: done ?? this.done,
      );
}

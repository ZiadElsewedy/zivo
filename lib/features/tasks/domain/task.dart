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

  Task copyWith({bool? done}) => Task(
        id: id,
        title: title,
        createdAt: createdAt,
        due: due,
        priority: priority,
        done: done ?? this.done,
      );
}

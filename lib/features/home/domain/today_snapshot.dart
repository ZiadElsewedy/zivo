import '../presentation/widgets/hue.dart';

/// Now/Next and Focus view models, built live from their repositories (see
/// `now_next_builder.dart` / `focus_builder.dart`) — never demo data.

class NowNext {
  const NowNext({
    required this.kind,
    required this.time,
    required this.title,
    required this.detail,
  });

  final String kind; // "Lecture"
  final String time; // "09:30 · in 2h"
  final String title; // "Data Structures"
  final String detail; // "Hall B · Dr. Naguib · bring assignment 2"
}

class FocusItem {
  const FocusItem({
    required this.title,
    required this.hue,
    this.meta,
    this.done = false,
    this.taskId, // set for rows backed by a task (tap to complete)
  });

  final String title;
  final ZHue hue;
  final String? meta; // "overdue", "due today"
  final bool done;
  final String? taskId;
}

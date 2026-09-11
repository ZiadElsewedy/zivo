import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/reminders/data/in_memory_reminders_repository.dart';
import 'package:zivo/features/reminders/domain/reminder.dart';

void main() {
  const reminder = Reminder(
    id: 'r1',
    label: 'Dinner',
    kind: ReminderKind.meal,
    hour: 19,
    minute: 0,
  );

  test('starts empty and exposes seeded reminders', () {
    expect(InMemoryRemindersRepository().current, isEmpty);
    expect(
      InMemoryRemindersRepository(initial: const [reminder]).current,
      const [reminder],
    );
  });

  test('save updates current and emits to watchers', () async {
    final repo = InMemoryRemindersRepository();
    final emitted = <List<Reminder>>[];
    final sub = repo.watch().listen(emitted.add);
    // Let the initial `yield _current` land before the save's stream event.
    await Future<void>.delayed(Duration.zero);

    await repo.save(const [reminder]);
    await Future<void>.delayed(Duration.zero);

    expect(repo.current, const [reminder]);
    // The initial empty list, then the saved one.
    expect(emitted.first, isEmpty);
    expect(emitted.last, const [reminder]);

    await sub.cancel();
    repo.dispose();
  });
}

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/time_ago.dart';
import '../../domain/note.dart';
import 'note_capture_page.dart';

/// A minimal Notes list — newest first, searchable text later.
class NotesListPage extends StatelessWidget {
  const NotesListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final notes = AppScope.of(context).notes;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Notes', style: AppText.cardTitle),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.ember,
        elevation: 2,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NoteCapturePage()),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<List<Note>>(
        stream: notes.watchAll(),
        initialData: notes.current,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Note>[];
          if (items.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ink3),
            );
          }
          if (items.isEmpty) {
            return Center(
              child: Text('No notes yet.', style: AppText.aside),
            );
          }
          final now = DateTime.now();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.hairline),
            itemBuilder: (context, i) => _NoteRow(
              items[i],
              now: now,
              onTap: () => _openEdit(context, items[i]),
              onDelete: () => notes.remove(items[i].id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, Note note) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteCapturePage(initial: note)),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow(
    this.note, {
    required this.now,
    required this.onTap,
    required this.onDelete,
  });

  final Note note;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('note-row-${note.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.flareText,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        note.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(fontSize: 14, color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(timeAgo(note.updatedAt, now), style: AppText.meta.copyWith(color: AppColors.ink3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

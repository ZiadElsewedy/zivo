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
            itemBuilder: (context, i) => _NoteRow(items[i], now: now),
          );
        },
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow(this.note, {required this.now});

  final Note note;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}

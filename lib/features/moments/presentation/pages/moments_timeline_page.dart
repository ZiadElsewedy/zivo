import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/time_ago.dart';
import '../../domain/moment.dart';
import 'moment_capture_page.dart';

/// A minimal moments timeline — newest first.
class MomentsTimelinePage extends StatelessWidget {
  const MomentsTimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final moments = AppScope.of(context).moments;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Moments', style: AppText.cardTitle),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.ember,
        elevation: 2,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MomentCapturePage()),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<List<Moment>>(
        stream: moments.watchAll(),
        initialData: moments.current,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Moment>[];
          if (items.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ink3),
            );
          }
          if (items.isEmpty) {
            return Center(child: Text('No moments yet.', style: AppText.aside));
          }
          final now = DateTime.now();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            itemCount: items.length,
            itemBuilder: (context, i) => _MomentCard(
              items[i],
              now: now,
              onTap: () => _openEdit(context, items[i]),
              onDelete: () => moments.remove(items[i].id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, Moment moment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MomentCapturePage(initial: moment)),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard(
    this.moment, {
    required this.now,
    required this.onTap,
    required this.onDelete,
  });

  final Moment moment;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('moment-row-${moment.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14, bottom: 18),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.flareText,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 3 / 2,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF1ECE2), Color(0xFFE7E0D3)],
                      ),
                    ),
                    child: moment.imagePath == null
                        ? const Center(
                            child: Icon(Icons.image_outlined, size: 28, color: AppColors.ink3),
                          )
                        : Image.file(File(moment.imagePath!), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(moment.caption, style: AppText.rowTitle),
                    ),
                    const SizedBox(width: 12),
                    Text(timeAgo(moment.takenAt, now), style: AppText.meta.copyWith(color: AppColors.ink3)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

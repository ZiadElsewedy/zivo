import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/time_ago.dart';
import '../../domain/workout.dart';
import '../../domain/workout_format.dart';
import 'workout_capture_page.dart';

/// The Workout history — logged sessions, newest first.
///
/// Dark, immersive — matching the live session and plan pages, on the
/// app-wide [AppColors] dark theme.
class WorkoutHistoryPage extends StatelessWidget {
  const WorkoutHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final workouts = AppScope.of(context).workouts;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink2),
        title: Text('Workout', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.pulse,
        elevation: 2,
        tooltip: 'Log workout',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkoutCapturePage()),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<List<Workout>>(
        stream: workouts.watchAll(),
        initialData: workouts.current,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _HistoryErrorState();
          }
          final items = snapshot.data ?? const <Workout>[];
          if (items.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const _HistoryLoadingState();
          }
          if (items.isEmpty) {
            return const _HistoryEmptyState();
          }
          final now = DateTime.now();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _WorkoutCard(
              items[i],
              now: now,
              onTap: () => _openEdit(context, items[i]),
              onDelete: () => workouts.remove(items[i].id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, Workout workout) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WorkoutCapturePage(initial: workout)),
    );
  }
}

/// The Lottie loading mark renders in a dark ink tone of its own — nearly
/// invisible directly on [AppColors.ground] — so it's recolored to the
/// dark palette's muted ink via a color filter, then given a touch of a
/// lighter (but still dark) backdrop for extra contrast.
class _HistoryLoadingState extends StatelessWidget {
  const _HistoryLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: const BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
        padding: const EdgeInsets.all(10),
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(AppColors.ink2, BlendMode.srcIn),
          child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _HistoryErrorState extends StatelessWidget {
  const _HistoryErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text(
              "Couldn't load this.",
              style: AppText.aside.copyWith(color: AppColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again in a moment.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No workouts yet.',
          style: AppText.aside.copyWith(color: AppColors.ink2),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard(
    this.workout, {
    required this.now,
    required this.onTap,
    required this.onDelete,
  });

  final Workout workout;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('workout-card-${workout.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.flare,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.pulse,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        workout.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      timeAgo(workout.performedAt, now),
                      style: AppText.meta.copyWith(color: AppColors.ink3),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  workout.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(fontSize: 14, color: AppColors.ink2),
                ),
                const SizedBox(height: 8),
                Text(
                  workoutMeta(workout),
                  style: AppText.meta.copyWith(color: AppColors.pulse),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

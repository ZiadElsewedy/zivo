import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/time_ago.dart';
import '../../domain/workout.dart';
import '../../domain/workout_format.dart';
import 'workout_capture_page.dart';

/// The Workout history — logged sessions, newest first. A Pulse surface.
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
        title: Text('Workout', style: AppText.cardTitle),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.pulseText,
        elevation: 2,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkoutCapturePage()),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<List<Workout>>(
        stream: workouts.watchAll(),
        initialData: workouts.current,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Workout>[];
          if (items.isEmpty) {
            return Center(child: Text('No workouts yet.', style: AppText.aside));
          }
          final now = DateTime.now();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _WorkoutCard(items[i], now: now),
          );
        },
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard(this.workout, {required this.now});

  final Workout workout;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
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
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
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
            style: AppText.meta.copyWith(color: AppColors.pulseText),
          ),
        ],
      ),
    );
  }
}
